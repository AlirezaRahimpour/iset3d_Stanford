function thisR = piRecipRectify(thisR,origin)
% Move the camera and objects so that the camera is at origin pointed along
% the z-axis
%
% Description
%
% See piRotate for the rotation matrices for the three axes
% See also
%

% Examples
%{
 thisR = piRecipeDefault('scene name','simple scene');
 piAssetGeometry(thisR,'inplane','xz');

 piCameraRotate(thisR,'y rot',10);
 thisR.get('lookat direction')
 piAssetGeometry(thisR,'inplane','xz');

 origin = [0 0 0];
 thisR = piRecipRectify(thisR,origin);
 thisR.get('lookat direction')

 piAssetGeometry(thisR);
 piAssetGeometry(thisR,'inplane','xy');

 thisR.set('fov',60);
 piWrite(thisR); scene = piRender(thisR,'render type','radiance');
 sceneWindow(scene);
%}

%% Find the camera position
from = thisR.get('camera position');

%% Move the camera to the specified origin

% Identify all the children of root
idChildren = thisR.get('asset','root','children');

if numel(idChildren) == 1
    tmp = split(thisR.get('asset',idChildren,'name'),'_');
    if isequal(tmp{end},'rectify')
        % No need to insert a rectify node.  It is there already.
    else
        % Create the rectify node below the root and before all other nodes
        rectNode = piAssetCreate('type','branch');
        rectNode.name = 'rectify';
        thisR.set('asset','root','add',rectNode);
    end
else
    % Create the rectify node below the root and before all other nodes
    rectNode = piAssetCreate('type','branch');
    rectNode.name = 'rectify';
    thisR.set('asset','root','add',rectNode);
end

% Get the rectify node under the root
idRectify = thisR.get('asset','rectify','id');

% Place all the previous children under rectify
for ii=1:numel(idChildren)
    thisR.set('asset',idChildren(ii),'parent',idRectify);
end
% thisR.show

%%  Translation

% The camera is handled separately from the objects
d = origin - from;
piCameraTranslate(thisR,'xshift',d(1), ...
    'yshift',d(2), ...
    'zshift',d(3));

% Set the translation of the rectify node
piAssetSet(thisR,idRectify,'translation',d);
% thisR.get('asset','rectify','translate')
% piAssetGeometry(thisR);
% piWrite(thisR); scene = piRender(thisR,'render type','radiance'); sceneWindow(scene);
 
%% Rotation

% Rotate the camera
[xAngle, yAngle] = direction2zaxis(thisR);

% No rotation needed.  Direction is already aligned with z axis.
if xAngle == 0 && yAngle == 0, return; end

% Rotate the to point onto the z axis
rMatrix = piRotate([xAngle,yAngle,0]);
to = thisR.get('to');
thisR.set('to',(rMatrix*to(:))');  % Row vector.  Should be forced in set.
% piWrite(thisR); scene = piRender(thisR,'render type','radiance'); sceneWindow(scene);

% Set a rotation in the rectify nodes to change all the objects
r = piRotationMatrix('zrot',0,'yrot',-yAngle,'xrot',-xAngle);
piAssetSet(thisR,idRectify,'rotation',r);
% thisR.get('asset','rectify','rotation')
% piWrite(thisR); [scene,results] = piRender(thisR,'render type','radiance'); sceneWindow(scene);

end

function [xAngle, yAngle] = direction2zaxis(thisR)
%% Angles needed to align lookat with zaxis
%
%  0 = [0   cos(a)  -sin(a)]*direction(:)
%  0 = cos(a)*direction(2) - sin(a)*direction(3)
%  sin(a)*direction(3) = cos(a)*direction(2)
%  sin(a)/cos(a) = (direction(2)/direction(3))
%  tan(a) = (direction(2)/direction(3))
%  a = atan(direction(2)/direction(3))
%
% Rotate again, this time to be perpendicular to the x-axis (x=0). 
%
%  0 =  cos(b)*d2(1) + 0*d2(2) +  sin(b)*d2(3)
%  sin(b)/cos(b) = -d2(1)/d2(3)
%  b = atan(-d2(1)/d2(3))

%
xAngle = 0; yAngle = 0;   % Assume aligned

% Angle to the z axis
direction = thisR.get('lookat direction');   % Unit vector
zaxis = [0 0 1];
CosTheta = max(min(dot(direction,zaxis),1),-1);
ztheta = real(acosd(CosTheta));

% If the direction is different from down the z-axis, do the rest.
% Otherwise, return.  We consider 'different' to be within a tenth of a
% degree, I guess.
%
if ztheta < 0.1, return; end

% Find the rotations in deg around the x and y axes so that the new
% direction vector aligns with the zaxis. 
%
% First find a rotation angle around the x-axis into the x-z plane.
% The angle must satisfy y = 0.  So, we take out the row of the x-rotation
% matrix
%

% Test with different direction vectors
%
% direction = [1 2 0];
% direction = [-1 0 2];
xAngle = atan2d(direction(2),direction(3));   % Radians
xRotationMatrix = piRotate([rad2deg(xAngle),0,0]);
direction2 = xRotationMatrix*direction(:);

%{
% y entry of this vector should be 0
  direction2
%}

% Now solve for y rotation
yAngle = atan2d(-direction2(1),direction2(3));

%{
 % Should be aligned with z-axis
 cos(yAngle)*direction2(1) + sin(yAngle)*direction2(3)
 yRotationMatrix = piRotate([0,rad2deg(yAngle),0]);
 direction3 = yRotationMatrix*direction2(:)
%}

end

%{

rMatrix = piRotate([xAngle,yAngle,0]);

% We have the angles.  Rotate every object's position and its orientation
for ii=1:numel(objects)
    pos = thisR.get('asset',objects(ii),'world coordinate');
    pos = rMatrix*pos(:);
    thisR.set('asset',objects(ii),'world coordinate',pos);
    piAssetRotate('asset',objects(ii),[xAngle,yAngle,0]);
end

end
%}

%{
% NOTES
u = zaxis; v = direction;

CosTheta = max(min(dot(u,v)/(norm(u)*norm(v)),1),-1);
ztheta = real(acosd(CosTheta));

xaxis = 

R = [cosd(theta) -sind(theta); sind(theta) cosd(theta)];
vR = v*R;
%}
% Find the 3D rotation matrix that brings direction to the zaxis.
% Call piDCM2angle to get the x,y,z rotations
% Call piAssetRotate with those three rotations

%}
