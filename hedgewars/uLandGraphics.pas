(*
 * Hedgewars, a free turn based strategy game
 * Copyright (c) 2004-2013 Andrey Korotaev <unC0Rr@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 2 of the License
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA
 *)

{$INCLUDE "options.inc"}

unit uLandGraphics;
interface
uses uFloat, uConsts, uTypes;

type
    fillType = (nullPixel, backgroundPixel, ebcPixel, icePixel, setNotCurrentMask, changePixelSetNotCurrent, setCurrentHog, changePixelNotSetNotCurrent);

type TRangeArray = array[0..31] of record
                                   Left, Right: LongInt;
                                   end;
     PRangeArray = ^TRangeArray;
TLandCircleProcedure = procedure (landX, landY, pixelX, pixelY: Longint);

function  addBgColor(OldColor, NewColor: LongWord): LongWord;
function  SweepDirty: boolean;
function  Despeckle(X, Y: LongInt): Boolean;
procedure Smooth(X, Y: LongInt);
function  CheckLandValue(X, Y: LongInt; LandFlag: Word): boolean;
function  DrawExplosion(X, Y, Radius: LongInt): Longword;
procedure DrawHLinesExplosions(ar: PRangeArray; Radius: LongInt; y, dY: LongInt; Count: Byte);
procedure DrawTunnel(X, Y, dX, dY: hwFloat; ticks, HalfWidth: LongInt);
procedure FillRoundInLand(X, Y, Radius: LongInt; Value: Longword);
function FillRoundInLand(X, Y, Radius: LongInt; fill: fillType): LongWord;
procedure ChangeRoundInLand(X, Y, Radius: LongInt; doSet, isCurrent: boolean);
function  LandBackPixel(x, y: LongInt): LongWord;
procedure DrawLine(X1, Y1, X2, Y2: LongInt; Color: Longword);
procedure DrawThickLine(X1, Y1, X2, Y2, radius: LongInt; color: Longword);
procedure DumpLandToLog(x, y, r: LongInt);
procedure DrawIceBreak(x, y, iceRadius, iceHeight: Longint);
function TryPlaceOnLand(cpX, cpY: LongInt; Obj: TSprite; Frame: LongInt; doPlace: boolean; indestructible: boolean): boolean;

implementation
uses SDLh, uLandTexture, uVariables, uUtils, uDebug;


procedure calculatePixelsCoordinates(landX, landY: Longint; var pixelX, pixelY: Longint); inline;
begin
if (cReducedQuality and rqBlurryLand) = 0 then
    begin
    pixelX := landX;
    pixelY := landY;
    end
else
    begin
    pixelX := LandX div 2;
    pixelY := LandY div 2;
    end;
end;

function drawPixelBG(landX, landY, pixelX, pixelY: Longint): Longword; inline;
begin
drawPixelBG := 0;
if (Land[LandY, landX] and lfIndestructible) = 0 then
    begin
        if ((Land[landY, landX] and lfBasic) <> 0) and (((LandPixels[pixelY, pixelX] and AMask) shr AShift) = 255) and (not disableLandBack) then
        begin
            LandPixels[pixelY, pixelX]:= LandBackPixel(landX, landY);
            inc(drawPixelBG);
        end
        else if ((Land[landY, landX] and lfObject) <> 0) or (((LandPixels[pixelY, pixelX] and AMask) shr AShift) < 255) then
            LandPixels[pixelY, pixelX]:= 0
    end;
end;

procedure drawPixelEBC(landX, landY, pixelX, pixelY: Longint); inline;
begin
if ((Land[landY, landX] and lfBasic) <> 0) or ((Land[landY, landX] and lfObject) <> 0) then
    begin
    LandPixels[pixelY, pixelX]:= ExplosionBorderColor;
    Land[landY, landX]:= (Land[landY, landX] or lfDamaged) and not lfIce;
    LandDirty[landY div 32, landX div 32]:= 1;
    end;
end;

function isLandscapeEdge(weight:Longint):boolean; inline;
begin
result := (weight < 8) and (weight >= 2);
end;

function getPixelWeight(x, y:Longint): Longint;
var
    i, j:Longint;
begin
result := 0;
for i := x - 1 to x + 1 do
    for j := y - 1 to y + 1 do
    begin
    if (i < 0) or
       (i > LAND_WIDTH - 1) or
       (j < 0) or
       (j > LAND_HEIGHT -1) then
       begin
       result := 9;
       exit;
       end;
    if Land[j, i] and lfLandMask and not lfIce = 0 then
       result := result + 1;
    end;
end;


procedure fillPixelFromIceSprite(pixelX, pixelY:Longint); inline;
var
    iceSurface: PSDL_Surface;
    icePixels: PLongwordArray;
    w: LongWord;
begin
    // So. 3 parameters here. Ice colour, Ice opacity, and a bias on the greyscaled pixel towards lightness
    iceSurface:= SpritesData[sprIceTexture].Surface;
    icePixels := iceSurface^.pixels;
    w:= LandPixels[pixelY, pixelX];
    if w > 0 then
        begin
        w:= round(((w shr RShift and $FF) * RGB_LUMINANCE_RED +
              (w shr BShift and $FF) * RGB_LUMINANCE_GREEN +
              (w shr GShift and $FF) * RGB_LUMINANCE_BLUE));
        if w < 128 then w:= w+128;
        if w > 255 then w:= 255;
        w:= (w shl RShift) or (w shl BShift) or (w shl GShift) or (LandPixels[pixelY, pixelX] and AMask);
        LandPixels[pixelY, pixelX]:= addBgColor(w, IceColor);
        LandPixels[pixelY, pixelX]:= addBgColor(LandPixels[pixelY, pixelX], icePixels^[iceSurface^.w * (pixelY mod iceSurface^.h) + (pixelX mod iceSurface^.w)])
        end
    else
        begin
        LandPixels[pixelY, pixelX]:= IceColor and not AMask or $E8 shl AShift;
        LandPixels[pixelY, pixelX]:= addBgColor(LandPixels[pixelY, pixelX], icePixels^[iceSurface^.w * (pixelY mod iceSurface^.h) + (pixelX mod iceSurface^.w)]);
        // silly workaround to avoid having to make background erasure a tadb it smarter about sea ice
        if LandPixels[pixelY, pixelX] and AMask shr AShift = 255 then
            LandPixels[pixelY, pixelX]:= LandPixels[pixelY, pixelX] and not AMask or 254 shl AShift;
        end;
end;


procedure DrawPixelIce(landX, landY, pixelX, pixelY: Longint); inline;
begin
if ((Land[landY, landX] and lfIce) <> 0) then exit;
if isLandscapeEdge(getPixelWeight(landX, landY)) then
    begin
    if (LandPixels[pixelY, pixelX] and AMask < 255) and (LandPixels[pixelY, pixelX] and AMask > 0) then
        LandPixels[pixelY, pixelX] := (IceEdgeColor and not AMask) or (LandPixels[pixelY, pixelX] and AMask)
    else if (LandPixels[pixelY, pixelX] and AMask < 255) or (Land[landY, landX] > 255) then
        LandPixels[pixelY, pixelX] := IceEdgeColor
    end
else if Land[landY, landX] > 255 then
    begin
        fillPixelFromIceSprite(pixelX, pixelY);
    end;
if Land[landY, landX] > 255 then Land[landY, landX] := Land[landY, landX] or lfIce and not lfDamaged;
end;


function FillLandCircleLine(y, fromPix, toPix: LongInt; fill : fillType): Longword;
var px, py, i: LongInt;
begin
//get rid of compiler warning
    px := 0;
    py := 0;
    FillLandCircleLine := 0;
    case fill of
    backgroundPixel:
    for i:= fromPix to toPix do
        begin
        calculatePixelsCoordinates(i, y, px, py);
        inc(FillLandCircleLine, drawPixelBG(i, y, px, py));
        end;
    ebcPixel:
    for i:= fromPix to toPix do
        begin
        calculatePixelsCoordinates(i, y, px, py);
        drawPixelEBC(i, y, px, py);
        end;
    nullPixel:
    for i:= fromPix to toPix do
        begin
        calculatePixelsCoordinates(i, y, px, py);
        if ((Land[y, i] and lfIndestructible) = 0) and (not disableLandBack or (Land[y, i] > 255))  then
            LandPixels[py, px]:= 0
        end;
    icePixel:
    for i:= fromPix to toPix do
        begin
        calculatePixelsCoordinates(i, y, px, py);
        DrawPixelIce(i, y, px, py);
        end;
    setNotCurrentMask:
    for i:= fromPix to toPix do
        begin
        Land[y, i]:= Land[y, i] and lfNotCurrentMask;
        end;
    changePixelSetNotCurrent:
    for i:= fromPix to toPix do
        begin
        if Land[y, i] and lfObjMask > 0 then
            Land[y, i]:= (Land[y, i] and lfNotObjMask) or ((Land[y, i] and lfObjMask) - 1);
        end;
    setCurrentHog:
    for i:= fromPix to toPix do
        begin
        Land[y, i]:= Land[y, i] or lfCurrentHog
        end;
    changePixelNotSetNotCurrent:
    for i:= fromPix to toPix do
        begin
        if Land[y, i] and lfObjMask < lfObjMask then
            Land[y, i]:= (Land[y, i] and lfNotObjMask) or ((Land[y, i] and lfObjMask) + 1)
        end;
    end;
end;

function FillLandCircleSegment(x, y, dx, dy: LongInt; fill : fillType): Longword; inline;
begin
    FillLandCircleSegment := 0;
if ((y + dy) and LAND_HEIGHT_MASK) = 0 then
    inc(FillLandCircleSegment, FillLandCircleLine(y + dy, Max(x - dx, 0), Min(x + dx, LAND_WIDTH - 1), fill));
if ((y - dy) and LAND_HEIGHT_MASK) = 0 then
    inc(FillLandCircleSegment, FillLandCircleLine(y - dy, Max(x - dx, 0), Min(x + dx, LAND_WIDTH - 1), fill));
if ((y + dx) and LAND_HEIGHT_MASK) = 0 then
    inc(FillLandCircleSegment, FillLandCircleLine(y + dx, Max(x - dy, 0), Min(x + dy, LAND_WIDTH - 1), fill));
if ((y - dx) and LAND_HEIGHT_MASK) = 0 then
    inc(FillLandCircleSegment, FillLandCircleLine(y - dx, Max(x - dy, 0), Min(x + dy, LAND_WIDTH - 1), fill));
end;

function FillRoundInLand(X, Y, Radius: LongInt; fill: fillType): Longword; inline;
var dx, dy, d: LongInt;
begin
dx:= 0;
dy:= Radius;
d:= 3 - 2 * Radius;
FillRoundInLand := 0;
while (dx < dy) do
    begin
    inc(FillRoundInLand, FillLandCircleSegment(x, y, dx, dy, fill));
    if (d < 0) then
        d:= d + 4 * dx + 6
    else
        begin
        d:= d + 4 * (dx - dy) + 10;
        dec(dy)
        end;
    inc(dx)
    end;
if (dx = dy) then
    inc (FillRoundInLand, FillLandCircleSegment(x, y, dx, dy, fill));
end;


function addBgColor(OldColor, NewColor: LongWord): LongWord;
// Factor ranges from 0 to 100% NewColor
var
    oRed, oBlue, oGreen, oAlpha, nRed, nBlue, nGreen, nAlpha: byte;
begin
    oAlpha := (OldColor shr AShift);
    nAlpha := (NewColor shr AShift);
    // shortcircuit
    if (oAlpha = 0) or (nAlpha = $FF) then
        begin
        addBgColor:= NewColor;
        exit
        end;
    // Get colors
    oRed   := (OldColor shr RShift);
    oGreen := (OldColor shr GShift);
    oBlue  := (OldColor shr BShift);

    nRed   := (NewColor shr RShift);
    nGreen := (NewColor shr GShift);
    nBlue  := (NewColor shr BShift);

    // Mix colors
    nRed   := min(255,((nRed*nAlpha) div 255) + ((oRed*oAlpha*byte(255-nAlpha)) div 65025));
    nGreen := min(255,((nGreen*nAlpha) div 255) + ((oGreen*oAlpha*byte(255-nAlpha)) div 65025));
    nBlue  := min(255,((nBlue*nAlpha) div 255) + ((oBlue*oAlpha*byte(255-nAlpha)) div 65025));
    nAlpha := min(255, oAlpha + nAlpha);

    addBgColor := (nAlpha shl AShift) or (nRed shl RShift) or (nGreen shl GShift) or (nBlue shl BShift);
end;

procedure FillCircleLines(x, y, dx, dy: LongInt; Value: Longword);
var i: LongInt;
begin
if ((y + dy) and LAND_HEIGHT_MASK) = 0 then
    for i:= Max(x - dx, 0) to Min(x + dx, LAND_WIDTH - 1) do
        if (Land[y + dy, i] and lfIndestructible) = 0 then
            Land[y + dy, i]:= Value;
if ((y - dy) and LAND_HEIGHT_MASK) = 0 then
    for i:= Max(x - dx, 0) to Min(x + dx, LAND_WIDTH - 1) do
        if (Land[y - dy, i] and lfIndestructible) = 0 then
            Land[y - dy, i]:= Value;
if ((y + dx) and LAND_HEIGHT_MASK) = 0 then
    for i:= Max(x - dy, 0) to Min(x + dy, LAND_WIDTH - 1) do
        if (Land[y + dx, i] and lfIndestructible) = 0 then
            Land[y + dx, i]:= Value;
if ((y - dx) and LAND_HEIGHT_MASK) = 0 then
    for i:= Max(x - dy, 0) to Min(x + dy, LAND_WIDTH - 1) do
        if (Land[y - dx, i] and lfIndestructible) = 0 then
            Land[y - dx, i]:= Value;
end;

procedure FillRoundInLand(X, Y, Radius: LongInt; Value: Longword);
var dx, dy, d: LongInt;
begin
dx:= 0;
dy:= Radius;
d:= 3 - 2 * Radius;
while (dx < dy) do
    begin
    FillCircleLines(x, y, dx, dy, Value);
    if (d < 0) then
        d:= d + 4 * dx + 6
    else
        begin
        d:= d + 4 * (dx - dy) + 10;
        dec(dy)
        end;
    inc(dx)
    end;
if (dx = dy) then
    FillCircleLines(x, y, dx, dy, Value);
end;

procedure ChangeRoundInLand(X, Y, Radius: LongInt; doSet, isCurrent: boolean);
begin
if not doSet and isCurrent then
    FillRoundInLand(X, Y, Radius, setNotCurrentMask)
else if not doSet and not IsCurrent then
    FillRoundInLand(X, Y, Radius, changePixelSetNotCurrent)
else if doSet and IsCurrent then
    FillRoundInLand(X, Y, Radius, setCurrentHog)
else if doSet and not IsCurrent then
    FillRoundInLand(X, Y, Radius, changePixelNotSetNotCurrent);
end;

procedure DrawIceBreak(x, y, iceRadius, iceHeight: Longint);
var
    i, j: integer;
    landRect: TSDL_Rect;
begin
for i := min(max(x - iceRadius, 0), LAND_WIDTH - 1) to min(max(x + iceRadius, 0), LAND_WIDTH - 1) do
    begin
    for j := min(max(y, 0), LAND_HEIGHT - 1) to min(max(y + iceHeight, 0), LAND_HEIGHT - 1) do
        begin
        if Land[j, i] = 0 then
            begin
            Land[j, i] := lfIce;
            fillPixelFromIceSprite(i, j);
            end;
        end;
    end;
landRect.x := min(max(x - iceRadius, 0), LAND_WIDTH - 1);
landRect.y := min(max(y, 0), LAND_HEIGHT - 1);
landRect.w := min(2*iceRadius, LAND_WIDTH - landRect.x - 1);
landRect.h := min(iceHeight, LAND_HEIGHT - landRect.y - 1);
UpdateLandTexture(landRect.x, landRect.w, landRect.y, landRect.h, true);
end;

function DrawExplosion(X, Y, Radius: LongInt): Longword;
var
    tx, ty, dx, dy: Longint;
begin
    DrawExplosion := FillRoundInLand(x, y, Radius, backgroundPixel);
    if Radius > 20 then
        FillRoundInLand(x, y, Radius - 15, nullPixel);
    FillRoundInLand(X, Y, Radius, 0);
    FillRoundInLand(x, y, Radius + 4, ebcPixel);
    tx:= Max(X - Radius - 5, 0);
    dx:= Min(X + Radius + 5, LAND_WIDTH) - tx;
    ty:= Max(Y - Radius - 5, 0);
    dy:= Min(Y + Radius + 5, LAND_HEIGHT) - ty;
    UpdateLandTexture(tx, dx, ty, dy, false);
end;

procedure DrawHLinesExplosions(ar: PRangeArray; Radius: LongInt; y, dY: LongInt; Count: Byte);
var tx, ty, by, bx,  i: LongInt;
begin
for i:= 0 to Pred(Count) do
    begin
    for ty:= Max(y - Radius, 0) to Min(y + Radius, LAND_HEIGHT) do
        for tx:= Max(0, ar^[i].Left - Radius) to Min(LAND_WIDTH, ar^[i].Right + Radius) do
            begin
            if (Land[ty, tx] and lfIndestructible) = 0 then
                begin
                if (cReducedQuality and rqBlurryLand) = 0 then
                    begin
                    by:= ty; bx:= tx;
                    end
                else
                    begin
                    by:= ty div 2; bx:= tx div 2;
                    end;
                if ((Land[ty, tx] and lfBasic) <> 0) and (((LandPixels[by,bx] and AMask) shr AShift) = 255) and (not disableLandBack) then
                    LandPixels[by, bx]:= LandBackPixel(tx, ty)
                else if ((Land[ty, tx] and lfObject) <> 0) or (((LandPixels[by,bx] and AMask) shr AShift) < 255) then
                    LandPixels[by, bx]:= 0
                end
            end;
    inc(y, dY)
    end;

inc(Radius, 4);
dec(y, Count * dY);

for i:= 0 to Pred(Count) do
    begin
    for ty:= Max(y - Radius, 0) to Min(y + Radius, LAND_HEIGHT) do
        for tx:= Max(0, ar^[i].Left - Radius) to Min(LAND_WIDTH, ar^[i].Right + Radius) do
            if ((Land[ty, tx] and lfBasic) <> 0) or ((Land[ty, tx] and lfObject) <> 0) then
                begin
                 if (cReducedQuality and rqBlurryLand) = 0 then
                    LandPixels[ty, tx]:= ExplosionBorderColor
                else
                    LandPixels[ty div 2, tx div 2]:= ExplosionBorderColor;

                Land[ty, tx]:= (Land[ty, tx] or lfDamaged) and not lfIce;
                LandDirty[ty div 32, tx div 32]:= 1;
                end;
    inc(y, dY)
    end;


UpdateLandTexture(0, LAND_WIDTH, 0, LAND_HEIGHT, false)
end;



procedure DrawExplosionBorder(X, Y, dx, dy:hwFloat;  despeckle : Boolean);
var
    t, tx, ty :Longint;
begin
for t:= 0 to 7 do
    begin
    X:= X + dX;
    Y:= Y + dY;
    tx:= hwRound(X);
    ty:= hwRound(Y);
    if ((ty and LAND_HEIGHT_MASK) = 0) and ((tx and LAND_WIDTH_MASK) = 0) and (((Land[ty, tx] and lfBasic) <> 0)
    or ((Land[ty, tx] and lfObject) <> 0)) then
        begin
        Land[ty, tx]:= (Land[ty, tx] or lfDamaged) and not lfIce;
        if despeckle then
            LandDirty[ty div 32, tx div 32]:= 1;
        if (cReducedQuality and rqBlurryLand) = 0 then
            LandPixels[ty, tx]:= ExplosionBorderColor
        else
            LandPixels[ty div 2, tx div 2]:= ExplosionBorderColor
        end
    end;
end;


//
//  - (dX, dY) - direction, vector of length = 0.5
//
procedure DrawTunnel(X, Y, dX, dY: hwFloat; ticks, HalfWidth: LongInt);
var nx, ny, dX8, dY8: hwFloat;
    i, t, tx, ty, by, bx, stX, stY, ddy, ddx: Longint;
    despeckle : Boolean;
begin  // (-dY, dX) is (dX, dY) rotated by PI/2
stY:= hwRound(Y);
stX:= hwRound(X);

despeckle:= HalfWidth > 1;

nx:= X + dY * (HalfWidth + 8);
ny:= Y - dX * (HalfWidth + 8);

dX8:= dX * 8;
dY8:= dY * 8;
for i:= 0 to 7 do
    begin
    X:= nx - dX8;
    Y:= ny - dY8;
    for t:= -8 to ticks + 8 do
    begin
    X:= X + dX;
    Y:= Y + dY;
    tx:= hwRound(X);
    ty:= hwRound(Y);
    if ((ty and LAND_HEIGHT_MASK) = 0)
    and ((tx and LAND_WIDTH_MASK) = 0)
    and (((Land[ty, tx] and lfBasic) <> 0) or ((Land[ty, tx] and lfObject) <> 0)) then
        begin
        Land[ty, tx]:= Land[ty, tx] and not lfIce;
        if despeckle then
            begin
            Land[ty, tx]:= Land[ty, tx] or lfDamaged;
            LandDirty[ty div 32, tx div 32]:= 1
            end;
        if (cReducedQuality and rqBlurryLand) = 0 then
            LandPixels[ty, tx]:= ExplosionBorderColor
        else
            LandPixels[ty div 2, tx div 2]:= ExplosionBorderColor
        end
    end;
    nx:= nx - dY;
    ny:= ny + dX;
    end;

for i:= -HalfWidth to HalfWidth do
    begin
    X:= nx - dX8;
    Y:= ny - dY8;
    DrawExplosionBorder(X, Y, dx, dy, despeckle);
    X:= nx;
    Y:= ny;
    for t:= 0 to ticks do
        begin
        X:= X + dX;
        Y:= Y + dY;
        tx:= hwRound(X);
        ty:= hwRound(Y);
        if ((ty and LAND_HEIGHT_MASK) = 0) and ((tx and LAND_WIDTH_MASK) = 0) and ((Land[ty, tx] and lfIndestructible) = 0) then
            begin
            if (cReducedQuality and rqBlurryLand) = 0 then
                begin
                by:= ty; bx:= tx;
                end
            else
                begin
                by:= ty div 2; bx:= tx div 2;
                end;
            if ((Land[ty, tx] and lfBasic) <> 0) and (((LandPixels[by,bx] and AMask) shr AShift) = 255) and (not disableLandBack) then
                LandPixels[by, bx]:= LandBackPixel(tx, ty)
            else if ((Land[ty, tx] and lfObject) <> 0) or (((LandPixels[by,bx] and AMask) shr AShift) < 255) then
                LandPixels[by, bx]:= 0;
            Land[ty, tx]:= 0;
            end
        end;
    DrawExplosionBorder(X, Y, dx, dy, despeckle);
    nx:= nx - dY;
    ny:= ny + dX;
    end;

for i:= 0 to 7 do
    begin
    X:= nx - dX8;
    Y:= ny - dY8;
    for t:= -8 to ticks + 8 do
    begin
    X:= X + dX;
    Y:= Y + dY;
    tx:= hwRound(X);
    ty:= hwRound(Y);
    if ((ty and LAND_HEIGHT_MASK) = 0) and ((tx and LAND_WIDTH_MASK) = 0) and (((Land[ty, tx] and lfBasic) <> 0)
    or ((Land[ty, tx] and lfObject) <> 0)) then
        begin
        Land[ty, tx]:= (Land[ty, tx] or lfDamaged) and not lfIce;
        if despeckle then
            LandDirty[ty div 32, tx div 32]:= 1;
        if (cReducedQuality and rqBlurryLand) = 0 then
            LandPixels[ty, tx]:= ExplosionBorderColor
        else
            LandPixels[ty div 2, tx div 2]:= ExplosionBorderColor
        end
    end;
    nx:= nx - dY;
    ny:= ny + dX;
    end;

tx:= Max(stX - HalfWidth * 2 - 4 - abs(hwRound(dX * ticks)), 0);
ty:= Max(stY - HalfWidth * 2 - 4 - abs(hwRound(dY * ticks)), 0);
ddx:= Min(stX + HalfWidth * 2 + 4 + abs(hwRound(dX * ticks)), LAND_WIDTH) - tx;
ddy:= Min(stY + HalfWidth * 2 + 4 + abs(hwRound(dY * ticks)), LAND_HEIGHT) - ty;

UpdateLandTexture(tx, ddx, ty, ddy, false)
end;

function TryPlaceOnLand(cpX, cpY: LongInt; Obj: TSprite; Frame: LongInt; doPlace: boolean; indestructible: boolean): boolean;
var X, Y, bpp, h, w, row, col, gx, gy, numFramesFirstCol: LongInt;
    p: PByteArray;
    Image: PSDL_Surface;
begin
TryPlaceOnLand:= false;
numFramesFirstCol:= SpritesData[Obj].imageHeight div SpritesData[Obj].Height;

TryDo(SpritesData[Obj].Surface <> nil, 'Assert SpritesData[Obj].Surface failed', true);
Image:= SpritesData[Obj].Surface;
w:= SpritesData[Obj].Width;
h:= SpritesData[Obj].Height;
row:= Frame mod numFramesFirstCol;
col:= Frame div numFramesFirstCol;

if SDL_MustLock(Image) then
    SDLTry(SDL_LockSurface(Image) >= 0, true);

bpp:= Image^.format^.BytesPerPixel;
TryDo(bpp = 4, 'It should be 32 bpp sprite', true);
// Check that sprite fits free space
p:= @(PByteArray(Image^.pixels)^[ Image^.pitch * row * h + col * w * 4 ]);
case bpp of
    4: for y:= 0 to Pred(h) do
        begin
        for x:= 0 to Pred(w) do
            if (PLongword(@(p^[x * 4]))^) <> 0 then
                if ((cpY + y) <= Longint(topY)) or ((cpY + y) >= LAND_HEIGHT) or
                   ((cpX + x) <= Longint(leftX)) or ((cpX + x) >= Longint(rightX)) or (Land[cpY + y, cpX + x] <> 0) then
                    begin
                        if SDL_MustLock(Image) then
                            SDL_UnlockSurface(Image);
                        exit;
                    end;
        p:= @(p^[Image^.pitch]);
        end;
    end;

TryPlaceOnLand:= true;
if not doPlace then
    begin
    if SDL_MustLock(Image) then
        SDL_UnlockSurface(Image);
    exit
    end;

// Checked, now place
p:= @(PByteArray(Image^.pixels)^[ Image^.pitch * row * h + col * w * 4 ]);
case bpp of
    4: for y:= 0 to Pred(h) do
        begin
        for x:= 0 to Pred(w) do
            if (PLongword(@(p^[x * 4]))^) <> 0 then
                   begin
                if (cReducedQuality and rqBlurryLand) = 0 then
                    begin
                    gX:= cpX + x;
                    gY:= cpY + y;
                    end
                else
                     begin
                     gX:= (cpX + x) div 2;
                     gY:= (cpY + y) div 2;
                    end;
                if indestructible then
                    Land[cpY + y, cpX + x]:= lfIndestructible
                else if (LandPixels[gY, gX] and AMask) shr AShift = 255 then  // This test assumes lfBasic and lfObject differ only graphically
                    Land[cpY + y, cpX + x]:= lfBasic
                else
                    Land[cpY + y, cpX + x]:= lfObject;
                // For testing only. Intent is to flag this on objects with masks, or use it for an ice ray gun
                if (Theme = 'Snow') or (Theme = 'Christmas') then
                    Land[cpY + y, cpX + x]:= Land[cpY + y, cpX + x] or lfIce;
                    LandPixels[gY, gX]:= PLongword(@(p^[x * 4]))^
                end;
        p:= @(p^[Image^.pitch]);
        end;
    end;
if SDL_MustLock(Image) then
    SDL_UnlockSurface(Image);

x:= Max(cpX, leftX);
w:= Min(cpX + Image^.w, LAND_WIDTH) - x;
y:= Max(cpY, topY);
h:= Min(cpY + Image^.h, LAND_HEIGHT) - y;
UpdateLandTexture(x, w, y, h, true)
end;

function Despeckle(X, Y: LongInt): boolean;
var nx, ny, i, j, c, xx, yy: LongInt;
    pixelsweep: boolean;
begin
    Despeckle:= true;

    if (cReducedQuality and rqBlurryLand) = 0 then
    begin
        xx:= X;
        yy:= Y;
    end
    else
    begin
        xx:= X div 2;
        yy:= Y div 2;
    end;

    pixelsweep:= (Land[Y, X] <= lfAllObjMask) and (LandPixels[yy, xx] <> 0);
    if (((Land[Y, X] and lfDamaged) <> 0) and ((Land[Y, X] and lfIndestructible) = 0)) or pixelsweep then
    begin
        c:= 0;
        for i:= -1 to 1 do
            for j:= -1 to 1 do
                if (i <> 0) or (j <> 0) then
                begin
                    ny:= Y + i;
                    nx:= X + j;
                    if ((ny and LAND_HEIGHT_MASK) = 0) and ((nx and LAND_WIDTH_MASK) = 0) then
                    begin
                        if pixelsweep then
                        begin
                            if ((cReducedQuality and rqBlurryLand) <> 0) then
                            begin
                                nx:= nx div 2;
                                ny:= ny div 2
                            end;
                            if LandPixels[ny, nx] <> 0 then
                                inc(c);
                        end
                    else if Land[ny, nx] > 255 then
                        inc(c);
                    end
                end;

        if c < 4 then // 0-3 neighbours
        begin
            if ((Land[Y, X] and lfBasic) <> 0) and (not disableLandBack) then
                LandPixels[yy, xx]:= LandBackPixel(X, Y)
            else
                LandPixels[yy, xx]:= 0;

            if not pixelsweep then
            begin
                Land[Y, X]:= 0;
                exit
            end
        end;
    end;
    Despeckle:= false
end;

procedure Smooth(X, Y: LongInt);
begin
// a bit of AA for explosions
if (Land[Y, X] = 0) and (Y > LongInt(topY) + 1) and
    (Y < LAND_HEIGHT-2) and (X > LongInt(leftX) + 1) and (X < LongInt(rightX) - 1) then
    begin
    if ((((Land[y, x-1] and lfDamaged) <> 0) and (((Land[y+1,x] and lfDamaged) <> 0)) or ((Land[y-1,x] and lfDamaged) <> 0))
    or (((Land[y, x+1] and lfDamaged) <> 0) and (((Land[y-1,x] and lfDamaged) <> 0) or ((Land[y+1,x] and lfDamaged) <> 0)))) then
        begin
        if (cReducedQuality and rqBlurryLand) = 0 then
            begin
            if ((LandPixels[y,x] and AMask) shr AShift) < 10 then
                LandPixels[y,x]:= (ExplosionBorderColor and (not AMask)) or (128 shl AShift)
            else
                LandPixels[y,x]:=
                                (((((LandPixels[y,x] and RMask shr RShift) div 2)+((ExplosionBorderColor and RMask) shr RShift) div 2) and $FF) shl RShift) or
                                (((((LandPixels[y,x] and GMask shr GShift) div 2)+((ExplosionBorderColor and GMask) shr GShift) div 2) and $FF) shl GShift) or
                                (((((LandPixels[y,x] and BMask shr BShift) div 2)+((ExplosionBorderColor and BMask) shr BShift) div 2) and $FF) shl BShift) or ($FF shl AShift)
            end;
        if (Land[y, x-1] = lfObject) then
            Land[y,x]:= lfObject
        else if (Land[y, x+1] = lfObject) then
            Land[y,x]:= lfObject
        else
            Land[y,x]:= lfBasic;
        end
    else if ((((Land[y, x-1] and lfDamaged) <> 0) and ((Land[y+1,x-1] and lfDamaged) <> 0) and ((Land[y+2,x] and lfDamaged) <> 0))
    or (((Land[y, x-1] and lfDamaged) <> 0) and ((Land[y-1,x-1] and lfDamaged) <> 0) and ((Land[y-2,x] and lfDamaged) <> 0))
    or (((Land[y, x+1] and lfDamaged) <> 0) and ((Land[y+1,x+1] and lfDamaged) <> 0) and ((Land[y+2,x] and lfDamaged) <> 0))
    or (((Land[y, x+1] and lfDamaged) <> 0) and ((Land[y-1,x+1] and lfDamaged) <> 0) and ((Land[y-2,x] and lfDamaged) <> 0))
    or (((Land[y+1, x] and lfDamaged) <> 0) and ((Land[y+1,x+1] and lfDamaged) <> 0) and ((Land[y,x+2] and lfDamaged) <> 0))
    or (((Land[y-1, x] and lfDamaged) <> 0) and ((Land[y-1,x+1] and lfDamaged) <> 0) and ((Land[y,x+2] and lfDamaged) <> 0))
    or (((Land[y+1, x] and lfDamaged) <> 0) and ((Land[y+1,x-1] and lfDamaged) <> 0) and ((Land[y,x-2] and lfDamaged) <> 0))
    or (((Land[y-1, x] and lfDamaged) <> 0) and ((Land[y-1,x-1] and lfDamaged) <> 0) and ((Land[y,x-2] and lfDamaged) <> 0))) then
        begin
        if (cReducedQuality and rqBlurryLand) = 0 then
            begin
            if ((LandPixels[y,x] and AMask) shr AShift) < 10 then
                LandPixels[y,x]:= (ExplosionBorderColor and (not AMask)) or (64 shl AShift)
            else
                LandPixels[y,x]:=
                                (((((LandPixels[y,x] and RMask shr RShift) * 3 div 4)+((ExplosionBorderColor and RMask) shr RShift) div 4) and $FF) shl RShift) or
                                (((((LandPixels[y,x] and GMask shr GShift) * 3 div 4)+((ExplosionBorderColor and GMask) shr GShift) div 4) and $FF) shl GShift) or
                                (((((LandPixels[y,x] and BMask shr BShift) * 3 div 4)+((ExplosionBorderColor and BMask) shr BShift) div 4) and $FF) shl BShift) or ($FF shl AShift)
            end;
        if (Land[y, x-1] = lfObject) then
            Land[y, x]:= lfObject
        else if (Land[y, x+1] = lfObject) then
            Land[y, x]:= lfObject
        else if (Land[y+1, x] = lfObject) then
            Land[y, x]:= lfObject
        else if (Land[y-1, x] = lfObject) then
        Land[y, x]:= lfObject
        else Land[y,x]:= lfBasic
        end
    end
else if ((cReducedQuality and rqBlurryLand) = 0) and (LandPixels[Y, X] and AMask = 255)
and (Land[Y, X] and (lfDamaged or lfBasic) = lfBasic)
and (Y > LongInt(topY) + 1) and (Y < LAND_HEIGHT-2) and (X > LongInt(leftX) + 1) and (X < LongInt(rightX) - 1) then
    begin
    if ((((Land[y, x-1] and lfDamaged) <> 0) and (((Land[y+1,x] and lfDamaged) <> 0)) or ((Land[y-1,x] and lfDamaged) <> 0))
    or (((Land[y, x+1] and lfDamaged) <> 0) and (((Land[y-1,x] and lfDamaged) <> 0) or ((Land[y+1,x] and lfDamaged) <> 0)))) then
        begin
        LandPixels[y,x]:=
                        (((((LandPixels[y,x] and RMask shr RShift) div 2)+((ExplosionBorderColor and RMask) shr RShift) div 2) and $FF) shl RShift) or
                        (((((LandPixels[y,x] and GMask shr GShift) div 2)+((ExplosionBorderColor and GMask) shr GShift) div 2) and $FF) shl GShift) or
                        (((((LandPixels[y,x] and BMask shr BShift) div 2)+((ExplosionBorderColor and BMask) shr BShift) div 2) and $FF) shl BShift) or ($FF shl AShift)
        end
    else if ((((Land[y, x-1] and lfDamaged) <> 0) and ((Land[y+1,x-1] and lfDamaged) <> 0) and ((Land[y+2,x] and lfDamaged) <> 0))
    or (((Land[y, x-1] and lfDamaged) <> 0) and ((Land[y-1,x-1] and lfDamaged) <> 0) and ((Land[y-2,x] and lfDamaged) <> 0))
    or (((Land[y, x+1] and lfDamaged) <> 0) and ((Land[y+1,x+1] and lfDamaged) <> 0) and ((Land[y+2,x] and lfDamaged) <> 0))
    or (((Land[y, x+1] and lfDamaged) <> 0) and ((Land[y-1,x+1] and lfDamaged) <> 0) and ((Land[y-2,x] and lfDamaged) <> 0))
    or (((Land[y+1, x] and lfDamaged) <> 0) and ((Land[y+1,x+1] and lfDamaged) <> 0) and ((Land[y,x+2] and lfDamaged) <> 0))
    or (((Land[y-1, x] and lfDamaged) <> 0) and ((Land[y-1,x+1] and lfDamaged) <> 0) and ((Land[y,x+2] and lfDamaged) <> 0))
    or (((Land[y+1, x] and lfDamaged) <> 0) and ((Land[y+1,x-1] and lfDamaged) <> 0) and ((Land[y,x-2] and lfDamaged) <> 0))
    or (((Land[y-1, x] and lfDamaged) <> 0) and ((Land[y-1,x-1] and lfDamaged) <> 0) and ((Land[y,x-2] and lfDamaged) <> 0))) then
        begin
        LandPixels[y,x]:=
                        (((((LandPixels[y,x] and RMask shr RShift) * 3 div 4)+((ExplosionBorderColor and RMask) shr RShift) div 4) and $FF) shl RShift) or
                        (((((LandPixels[y,x] and GMask shr GShift) * 3 div 4)+((ExplosionBorderColor and GMask) shr GShift) div 4) and $FF) shl GShift) or
                        (((((LandPixels[y,x] and BMask shr BShift) * 3 div 4)+((ExplosionBorderColor and BMask) shr BShift) div 4) and $FF) shl BShift) or ($FF shl AShift)
        end
    end
end;

function SweepDirty: boolean;
var x, y, xx, yy, ty, tx: LongInt;
    bRes, updateBlock, resweep, recheck: boolean;
begin
bRes:= false;
reCheck:= true;

while recheck do
    begin
    recheck:= false;
    for y:= 0 to LAND_HEIGHT div 32 - 1 do
        begin
        for x:= 0 to LAND_WIDTH div 32 - 1 do
            begin
            if LandDirty[y, x] = 1 then
                begin
                updateBlock:= false;
                resweep:= true;
                ty:= y * 32;
                tx:= x * 32;
                while(resweep) do
                    begin
                    resweep:= false;
                    for yy:= ty to ty + 31 do
                        for xx:= tx to tx + 31 do
                            if Despeckle(xx, yy) then
                                begin
                                bRes:= true;
                                updateBlock:= true;
                                resweep:= true;
                                if (yy = ty) and (y > 0) then
                                    begin
                                    LandDirty[y-1, x]:= 1;
                                    recheck:= true;
                                    end
                                else if (yy = ty+31) and (y < LAND_HEIGHT div 32 - 1) then
                                    begin
                                    LandDirty[y+1, x]:= 1;
                                    recheck:= true;
                                    end;
                                if (xx = tx) and (x > 0) then
                                    begin
                                    LandDirty[y, x-1]:= 1;
                                    recheck:= true;
                                    end
                                else if (xx = tx+31) and (x < LAND_WIDTH div 32 - 1) then
                                    begin
                                    LandDirty[y, x+1]:= 1;
                                    recheck:= true;
                                    end
                                end;
                    end;
                if updateBlock then
                    UpdateLandTexture(tx, 32, ty, 32, false);
                LandDirty[y, x]:= 2;
                end;
            end;
        end;
     end;

for y:= 0 to LAND_HEIGHT div 32 - 1 do
    for x:= 0 to LAND_WIDTH div 32 - 1 do
        if LandDirty[y, x] <> 0 then
            begin
            LandDirty[y, x]:= 0;
            ty:= y * 32;
            tx:= x * 32;
            for yy:= ty to ty + 31 do
                for xx:= tx to tx + 31 do
                    Smooth(xx,yy)
            end;

SweepDirty:= bRes;
end;


// Return true if outside of land or not the value tested, used right now for some X/Y movement that does not use normal hedgehog movement in GSHandlers.inc
function CheckLandValue(X, Y: LongInt; LandFlag: Word): boolean; inline;
begin
    CheckLandValue:= ((X and LAND_WIDTH_MASK <> 0) or (Y and LAND_HEIGHT_MASK <> 0)) or ((Land[Y, X] and LandFlag) = 0)
end;

function LandBackPixel(x, y: LongInt): LongWord; inline;
var p: PLongWordArray;
begin
    if LandBackSurface = nil then
        LandBackPixel:= 0
    else
        begin
        p:= LandBackSurface^.pixels;
        LandBackPixel:= p^[LandBackSurface^.w * (y mod LandBackSurface^.h) + (x mod LandBackSurface^.w)];// or $FF000000;
        end
end;


procedure DrawLine(X1, Y1, X2, Y2: LongInt; Color: Longword);
var
  eX, eY, dX, dY: LongInt;
  i, sX, sY, x, y, d: LongInt;
begin
eX:= 0;
eY:= 0;
dX:= X2 - X1;
dY:= Y2 - Y1;

if (dX > 0) then
    sX:= 1
else
    if (dX < 0) then
        begin
        sX:= -1;
        dX:= -dX
        end
    else
        sX:= dX;

if (dY > 0) then
    sY:= 1
else
    if (dY < 0) then
        begin
        sY:= -1;
        dY:= -dY
        end
    else
        sY:= dY;

if (dX > dY) then
    d:= dX
else
    d:= dY;

x:= X1;
y:= Y1;

for i:= 0 to d do
    begin
    inc(eX, dX);
    inc(eY, dY);
    if (eX > d) then
        begin
        dec(eX, d);
        inc(x, sX);
        end;
    if (eY > d) then
        begin
        dec(eY, d);
        inc(y, sY);
        end;

    if ((x and LAND_WIDTH_MASK) = 0) and ((y and LAND_HEIGHT_MASK) = 0) then
        Land[y, x]:= Color;
    end
end;

procedure DrawDots(x, y, xx, yy: Longint; Color: Longword); inline;
begin
    if (((x + xx) and LAND_WIDTH_MASK) = 0) and (((y + yy) and LAND_HEIGHT_MASK) = 0) then Land[y + yy, x + xx]:= Color;
    if (((x + xx) and LAND_WIDTH_MASK) = 0) and (((y - yy) and LAND_HEIGHT_MASK) = 0) then Land[y - yy, x + xx]:= Color;
    if (((x - xx) and LAND_WIDTH_MASK) = 0) and (((y + yy) and LAND_HEIGHT_MASK) = 0) then Land[y + yy, x - xx]:= Color;
    if (((x - xx) and LAND_WIDTH_MASK) = 0) and (((y - yy) and LAND_HEIGHT_MASK) = 0) then Land[y - yy, x - xx]:= Color;
    if (((x + yy) and LAND_WIDTH_MASK) = 0) and (((y + xx) and LAND_HEIGHT_MASK) = 0) then Land[y + xx, x + yy]:= Color;
    if (((x + yy) and LAND_WIDTH_MASK) = 0) and (((y - xx) and LAND_HEIGHT_MASK) = 0) then Land[y - xx, x + yy]:= Color;
    if (((x - yy) and LAND_WIDTH_MASK) = 0) and (((y + xx) and LAND_HEIGHT_MASK) = 0) then Land[y + xx, x - yy]:= Color;
    if (((x - yy) and LAND_WIDTH_MASK) = 0) and (((y - xx) and LAND_HEIGHT_MASK) = 0) then Land[y - xx, x - yy]:= Color;
end;

procedure DrawLines(X1, Y1, X2, Y2, XX, YY: LongInt; color: Longword);
var
  eX, eY, dX, dY: LongInt;
  i, sX, sY, x, y, d: LongInt;
  f: boolean;
begin
    eX:= 0;
    eY:= 0;
    dX:= X2 - X1;
    dY:= Y2 - Y1;

    if (dX > 0) then
        sX:= 1
    else
        if (dX < 0) then
            begin
            sX:= -1;
            dX:= -dX
            end
        else
            sX:= dX;

    if (dY > 0) then
        sY:= 1
    else
        if (dY < 0) then
            begin
            sY:= -1;
            dY:= -dY
            end
        else
            sY:= dY;

    if (dX > dY) then
        d:= dX
    else
        d:= dY;

    x:= X1;
    y:= Y1;

    for i:= 0 to d do
        begin
        inc(eX, dX);
        inc(eY, dY);

        f:= eX > d;
        if f then
            begin
            dec(eX, d);
            inc(x, sX);
            DrawDots(x, y, xx, yy, color)
            end;
        if (eY > d) then
            begin
            dec(eY, d);
            inc(y, sY);
            f:= true;
            DrawDots(x, y, xx, yy, color)
            end;

        if not f then
            DrawDots(x, y, xx, yy, color)
        end
end;

procedure DrawThickLine(X1, Y1, X2, Y2, radius: LongInt; color: Longword);
var dx, dy, d: LongInt;
begin
    dx:= 0;
    dy:= Radius;
    d:= 3 - 2 * Radius;
    while (dx < dy) do
        begin
        DrawLines(x1, y1, x2, y2, dx, dy, color);
        if (d < 0) then
            d:= d + 4 * dx + 6
        else
            begin
            d:= d + 4 * (dx - dy) + 10;
            dec(dy)
            end;
        inc(dx)
        end;
    if (dx = dy) then
        DrawLines(x1, y1, x2, y2, dx, dy, color);
end;


procedure DumpLandToLog(x, y, r: LongInt);
var xx, yy, dx: LongInt;
    s: shortstring;
begin
    s[0]:= char(r * 2 + 1);
    for yy:= y - r to y + r do
        begin
        for dx:= 0 to r*2 do
            begin
            xx:= dx - r + x;
            if (xx = x) and (yy = y) then
                s[dx + 1]:= 'X'
            else if Land[yy, xx] > 255 then
                s[dx + 1]:= 'O'
            else if Land[yy, xx] > 0 then
                s[dx + 1]:= '*'
            else
                s[dx + 1]:= '.'
            end;
        AddFileLog('Land dump: ' + s);
        end;
end;

end.
