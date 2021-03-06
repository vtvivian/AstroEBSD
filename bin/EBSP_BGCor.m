function [ EBSP2,outputs ] = EBSP_BGCor( EBSP,Settings_Cor )
%EBSP_BGCOR Background correct the EBSP
%Use as [ EBSP2,outputs ] = EBSP_BGCor( EBSP,Settings_Cor )
%Inputs
%EBSP - array that contains the EBSP
%Settings_Cor - structure that contains information
%               on how backgroudn correction should be performed
%
%               As an example set:
%
% %background correction
% Settings_Cor.gfilt=1; %use a low pass filter
% Settings_Cor.gfilt_s=5; %low pass filter sigma
% 
% %radius mask
% Settings_Cor.radius=1; %use a radius mask
% Settings_Cor.radius_frac=0.9; %fraction of the pattern width to use as the mask
% 
% %hold pixel
% Settings_Cor.hotpixel=1; %hot pixel correction
% Settings_Cor.hot_thresh=1000; %hot pixel threshold
% 
% %resize
% Settings_Cor.resize=1; %resize correction
% Settings_Cor.size=150; %image width
% 
% Settings_Cor.RealBG=0; %use a real BG
% Settings_Cor.EBSP_bgnum=30; %number of real pattern to use for BG
%
%OUTPUTS
%   EBSP2 = corrected ESBP array (as double)
%   outputs = information from corrections as a structure
%

%% Versioning
%v1 - TBB 14/04/2017

%% Start Code
outputs=struct;

EBSP2=EBSP;

%check fields exist & create if needed - this is ordered in the order of
%operations to aid with debugging & adding new correction routines 
%as needed

if ~isfield(Settings_Cor,'hotpixel')
    Settings_Cor.hotpixel=0;
end

if ~isfield(Settings_Cor,'resize')
    Settings_Cor.resize=0;
end

if ~isfield(Settings_Cor,'gaussfit')
    Settings_Cor.gaussfit=0;
end

if ~isfield(Settings_Cor,'blur')
    Settings_Cor.blur=0;
end

if ~isfield(Settings_Cor,'RealBG')
    Settings_Cor.RealBG=0;
end

if ~isfield(Settings_Cor,'radius')
    Settings_Cor.radius=0;
end

if ~isfield(Settings_Cor,'gfilt')
    Settings_Cor.gfilt=0;
end

%% Start the corrections
%cor the pattern for hot pixels
if Settings_Cor.hotpixel == 1
    [EBSP2,outputs.hotpixl_num]=cor_hotpix(EBSP2,Settings_Cor.hot_thresh);
end

if Settings_Cor.RealBG == 1
    EBSP2=EBSP2./Settings_Cor.EBSP_bg;
end


%fix the mean and std
EBSP2=fix_mean(EBSP2);

%resize the image
if Settings_Cor.resize == 1
    cs=floor([Settings_Cor.size Settings_Cor.size*size(EBSP,2)/size(EBSP,1)]);
    EBSP2 = imresize(EBSP2,cs);
else
    cs=size(EBSP2);
end
outputs.size=cs;


if Settings_Cor.gfilt == 1
    gf=Settings_Cor.gfilt_s*size(EBSP2,1)/100;
    EBSP2B = imgaussfilt(EBSP2,gf);
    EBSP2 = EBSP2./EBSP2B;
end


if Settings_Cor.gaussfit == 1
    
    EBSPData.PW=size(EBSP2,2);
    EBSPData.PH=size(EBSP2,1);
    [bg2,outputs.gaussparams]=bg_fit(EBSP2,EBSPData);
    EBSP2=EBSP2./bg2;
    EBSP2=fix_mean(EBSP2);
end

if Settings_Cor.blur == 1
    ix=size(EBSP2,2);
    Iblur = imgaussfilt(EBSP2, Settings_Cor.blurf(1),'filtersize',Settings_Cor.blurf(2));
    EBSP2=EBSP2-Iblur;
end

if Settings_Cor.radius == 1
    
    r_thresh=Settings_Cor.radius_frac*4/3*cs(1)/2;
    
    [xgrid,ygrid]=meshgrid(1:cs(2),1:cs(1));
    r_grid=sqrt((xgrid-size(EBSP2,2)/2).^2+(ygrid-size(EBSP2,1)/2).^2);
    EBSP2(r_grid>=r_thresh) = 0;
    EBSP2(r_grid<r_thresh)=  EBSP2(r_grid<r_thresh)-mean(EBSP2(r_grid<r_thresh));
else
    EBSP2=fix_mean(EBSP2);
end

end

function [EBSP2,num_hot]=cor_hotpix(EBSP,hthresh)

%Image correction - modified from JH code
%median filter
EBSP_med = medfilt2(EBSP);

%hot pixel correct
h_pix=find((EBSP-EBSP_med)>hthresh); %1000 is chosen as an arbitary number
EBSP2=EBSP;
EBSP2(h_pix)=EBSP_med(h_pix);
num_hot=size(h_pix);

end

function EBSP2=fix_mean(EBSP)
%zero mean & fix stdev
EBSP2=(EBSP-mean(EBSP(:)))/std(EBSP(:));
%make positive
EBSP2=EBSP2-min(EBSP2(:))+1;
end

function [bg2,params1]=bg_fit(EBSP2,EBSPData)
%build an image grid for bg fitting
ygv=1:1:EBSPData.PH;
xgv=1:1:EBSPData.PW;
[xgr,ygr] = meshgrid(xgv,ygv);

xsize=EBSPData.PW;

[xmax,ixv]=max(EBSP2);
[mv,iy]=max(xmax);
ix=ixv(iy);
range_e=mv-min(EBSP2(:));

params=[      ix            EBSPData.PH/4       iy            EBSPData.PH/4     range_e 1      range_e  1];

bg_dif=@(params,xgr,ygr,xsize,EBSP2)(abs(x_bg( params,xgr,ygr,xsize)./EBSP2-1));
singleval=@(x)(sum(x(:)));

fun_bg_solve=@(params)(singleval(bg_dif( params,xgr,ygr,xsize,EBSP2)));

[params1,fval] = fminsearch(fun_bg_solve,params);

bg2=x_bg( params1,xgr,ygr,xsize);
end

function [ bg ] = x_bg( params,xgr,ygr,xsize)
%X_BG Summary of this function goes here
%   Detailed explanation goes here

bg= exp( - ((((xgr-params(1)).^2)./(2*(params(2).^2))) + (((ygr-params(3)).^2)./(2*(params(4).^2)))));

bg(:,1:xsize/2)=params(5)*bg(:,1:xsize/2)+params(6);
bg(:,xsize/2+1:end)=params(7)*bg(:,xsize/2+1:end)+params(8);

end