(* Copyright (C)  Doom 2D: Forever Developers
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3 of the License ONLY.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *)
{$INCLUDE ../../../shared/a_modes.inc}
unit r_common;

interface

  uses r_textures;

  type
    TBasePoint = (
      BP_LEFTUP,   BP_UP,     BP_RIGHTUP,
      BP_LEFT,     BP_CENTER, BP_RIGHT,
      BP_LEFTDOWN, BP_DOWN,   BP_RIGHTDOWN
    );

    THereTexture = record
      name: AnsiString;
      id: TGLTexture;
    end;

  var
    stdfont: TGLFont;
    smallfont: TGLFont;
    menufont: TGLFont;

  function  r_Common_LoadThis (const name: AnsiString; var here: THereTexture): Boolean;
  procedure r_Common_FreeThis (var here: THereTexture);

  procedure r_Common_CalcAspect (ow, oh, nw, nh: LongInt; horizontal: Boolean; out ww, hh: LongInt);

  procedure r_Common_GetBasePoint (x, y, w, h: Integer; p: TBasePoint; out xx, yy: Integer);
  procedure r_Common_DrawText (const text: AnsiString; x, y: Integer; r, g, b, a: Byte; f: TGLFont; p: TBasePoint);
  procedure r_Common_DrawTexture (img: TGLTexture; x, y, w, h: Integer; p: TBasePoint);
  procedure r_Common_GetFormatTextSize (const text: AnsiString; f: TGLFont; out w, h: Integer);
  procedure r_Common_DrawFormatText (const text: AnsiString; x, y: Integer; a: Byte; f: TGLFont; p: TBasePoint);

  function r_Common_TimeToStr (t: LongWord): AnsiString;

  procedure r_Common_Load;
  procedure r_Common_Free;

implementation

  uses Math, SysUtils, g_base, e_log, utils, r_draw, r_fonts, g_options;

  procedure r_Common_GetBasePoint (x, y, w, h: Integer; p: TBasePoint; out xx, yy: Integer);
  begin
    case p of
      TBasePoint.BP_LEFTUP,  TBasePoint.BP_LEFT,   TBasePoint.BP_LEFTDOWN:  xx := x;
      TBasePoint.BP_UP,      TBasePoint.BP_CENTER, TBasePoint.BP_DOWN:      xx := x - w div 2;
      TBasePoint.BP_RIGHTUP, TBasePoint.BP_RIGHT,  TBasePoint.BP_RIGHTDOWN: xx := x - w;
    end;
    case p of
      TBasePoint.BP_LEFTUP,   TBasePoint.BP_UP,     TBasePoint.BP_RIGHTUP:   yy := y;
      TBasePoint.BP_LEFT,     TBasePoint.BP_CENTER, TBasePoint.BP_RIGHT:     yy := y - h div 2;
      TBasePoint.BP_LEFTDOWN, TBasePoint.BP_DOWN,   TBasePoint.BP_RIGHTDOWN: yy := y - h;
    end;
  end;

  procedure r_Common_DrawText (const text: AnsiString; x, y: Integer; r, g, b, a: Byte; f: TGLFont; p: TBasePoint);
    var xx, yy, w, h: Integer;
  begin
    xx := x; yy := y;
    if p <> TBasePoint.BP_LEFTUP then
    begin
      r_Draw_GetTextSize(text, f, w, h);
      r_Common_GetBasePoint(x, y, w, h, p, xx, yy);
    end;
    r_Draw_Text(text, xx, yy, r, g, b, a, f);
  end;

  procedure r_Common_DrawTexture (img: TGLTexture; x, y, w, h: Integer; p: TBasePoint);
  begin
    r_Common_GetBasePoint(x, y, w, h, p, x, y);
    r_Draw_TextureRepeat(img, x, y, w, h, false, 255, 255, 255, 255, false);
  end;

  procedure r_Common_GetFormatTextSize (const text: AnsiString; f: TGLFont; out w, h: Integer);
    var i, cw, ch, cln, curw, curh, maxw, maxh: Integer;
  begin
    curw := 0; curh := 0; maxw := 0; maxh := 0;
    r_Draw_GetTextSize('W', f, cw, cln);
    for i := 1 to Length(text) do
    begin
      case text[i] of
        #10:
        begin
          maxw := MAX(maxw, curw);
          curh := curh + cln;
          curw := 0;
        end;
        #1, #2, #3, #4, #18, #19, #20, #21:
        begin
          // skip color modifiers
        end;
        otherwise
        begin
          r_Draw_GetTextSize(text[i], f, cw, ch);
          maxh := MAX(maxh, curh + ch);
          curw := curw + cw;
        end;
      end;
    end;
    w := MAX(maxw, curw);
    h := MAX(maxh, curh);
  end;

  procedure r_Common_DrawFormatText (const text: AnsiString; x, y: Integer; a: Byte; f: TGLFont; p: TBasePoint);
    const
      colors: array [boolean, 0..5] of TRGB = (
        ((R:$00; G:$00; B:$00), (R:$FF; G:$00; B:$00), (R:$00; G:$FF; B:$00), (R:$FF; G:$FF; B:$00), (R:$00; G:$00; B:$FF), (R:$FF; G:$FF; B:$FF)),
        ((R:$00; G:$00; B:$00), (R:$7F; G:$00; B:$00), (R:$00; G:$7F; B:$00), (R:$FF; G:$7F; B:$00), (R:$00; G:$00; B:$7F), (R:$7F; G:$7F; B:$7F))
      );
    var
      i, xx, yy, cx, cy, w, h, cw, ch, cln, color: Integer; dark: Boolean;
  begin
    xx := x; yy := y;
    if p <> TBasePoint.BP_LEFTUP then
    begin
      r_Common_GetFormatTextSize(text, f, w, h);
      r_Common_GetBasePoint(x, y, w, h, p, xx, yy);
    end;
    cx := xx; cy := yy; color := 5; dark := false;
    r_Draw_GetTextSize('W', f, cw, cln);
    for i := 1 to Length(text) do
    begin
      case text[i] of
        #10:
        begin
          cx := xx;
          INC(cy, cln);
        end;
        #1: color := 0;
        #2: color := 5;
        #3: dark := true;
        #4: dark := false;
        #18: color := 1;
        #19: color := 2;
        #20: color := 4;
        #21: color := 3;
        otherwise
        begin
          r_Draw_GetTextSize(text[i], f, cw, ch);
          r_Draw_Text(text[i], cx, cy, colors[dark, color].R, colors[dark, color].G, colors[dark, color].B, a, f);
          INC(cx, cw);
        end;
      end;
    end;
  end;

  function r_Common_TimeToStr (t: LongWord): AnsiString;
    var h, m, s: Integer;
  begin
    h := t div 1000 div 3600;
    m := t div 1000 div 60 mod 60;
    s := t div 1000 mod 60;
    result := Format('%d:%.2d:%.2d', [h, m, s]);
  end;

  (* ---------  --------- *)

  procedure r_Common_FreeThis (var here: THereTexture);
  begin
    here.name := '';
    if here.id <> nil then
      here.id.Free;
    here.id := nil;
  end;

  function r_Common_LoadThis (const name: AnsiString; var here: THereTexture): Boolean;
  begin
    if name <> here.name then
      r_Common_FreeThis(here);
    if (name <> '') and (here.name <> name) then
      here.id := r_Textures_LoadFromFile(name);

    result := here.id <> nil;

    if result then
      here.name := name;
  end;

  procedure r_Common_CalcAspect (ow, oh, nw, nh: LongInt; horizontal: Boolean; out ww, hh: LongInt);
  begin
    if horizontal then
    begin
      ww := nw;
      hh := nw * oh div ow;
    end
    else
    begin
      ww := nh * ow div oh;
      hh := nh;
    end;
  end;

  function r_Common_LoadFont (const name: AnsiString): TGLFont;
    var info: TFontInfo; skiphack: Integer;
  begin
    result := nil;
    if name = 'STD' then skiphack := 144 else skiphack := 0;
    if r_Font_LoadInfoFromFile(GameWad + ':FONTS/' + name + 'TXT', info) then
      result := r_Textures_LoadFontFromFile(GameWad + ':FONTS/' + name + 'FONT', info, skiphack, true);
    if result = nil then
      e_logwritefln('failed to load font %s', [name]);
  end;

  procedure r_Common_Load;
  begin
    stdfont := r_Common_LoadFont('STD');
    smallfont := r_Common_LoadFont('SMALL');
    menufont := r_Common_LoadFont('MENU');
  end;

  procedure r_Common_Free;
  begin
    menufont.Free;
    smallfont.Free;
    stdfont.Free;
  end;

end.
