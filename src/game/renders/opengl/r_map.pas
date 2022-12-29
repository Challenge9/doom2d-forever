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
unit r_map;

interface

  uses g_base, g_player, g_playermodel; // TRectWH, TPlayer, TPlayerModel

  procedure r_Map_Initialize;
  procedure r_Map_Finalize;

  procedure r_Map_Load;
  procedure r_Map_Free;

  procedure r_Map_LoadTextures;
  procedure r_Map_FreeTextures;

{$IFDEF ENABLE_GFX}
  procedure r_Map_NewGFX (typ, x, y: Integer);
{$ENDIF}
{$IFDEF ENABLE_GIBS}
  function r_Map_GetGibSize (m, i: Integer): TRectWH;
{$ENDIF}
{$IFDEF ENABLE_MENU}
  procedure r_Map_DrawPlayerModel (pm: TPlayerModel; x, y: Integer; alpha: Byte);
{$ENDIF}

  procedure r_Map_Update;

  procedure r_Map_Draw (x, y, w, h, camx, camy: Integer; player: TPlayer);

implementation

  uses
    Math, SysUtils,
    {$IFDEF USE_GLES1}
      GLES11,
    {$ELSE}
      GL, GLEXT,
    {$ENDIF}
    e_log,
    binheap, MAPDEF, utils,
    g_options, g_animations, g_basic, g_phys,
    g_game, g_map, g_panel, g_items, g_monsters, g_weapons,
    g_console, g_language,
    {$IFDEF ENABLE_CORPSES}
      g_corpses,
    {$ENDIF}
    {$IFDEF ENABLE_SHELLS}
      g_shells,
    {$ENDIF}
    {$IFDEF ENABLE_GIBS}
      g_gibs,
    {$ENDIF}
    {$IFDEF ENABLE_GFX}
      g_gfx,
    {$ENDIF}
    r_textures, r_draw, r_common
  ;

  const
    MTABLE: array [0..MONSTER_MAN] of record
      w, h: Integer;
    end = (
      (w: 64;  h: 64),  // NONE
      (w: 64;  h: 64),  // DEMON
      (w: 64;  h: 64),  // IMP
      (w: 64;  h: 64),  // ZOMBY
      (w: 64;  h: 64),  // SERG
      (w: 128; h: 128), // CYBER
      (w: 64;  h: 64),  // CGUN
      (w: 128; h: 128), // BARON
      (w: 128; h: 128), // KNIGHT
      (w: 128; h: 128), // CACO
      (w: 64;  h: 64),  // SOUL (DIE is 128x128, see load code)
      (w: 128; h: 128), // PAIN
      (w: 256; h: 128), // SPIDER
      (w: 128; h: 64),  // BSP
      (w: 128; h: 128), // MANCUB
      (w: 128; h: 128), // SKEL
      (w: 128; h: 128), // VILE
      (w: 32;  h: 32),  // FISH
      (w: 64;  h: 64),  // BARREL
      (w: 128; h: 128), // ROBO
      (w: 64;  h: 64)   // MAN
    );
    VILEFIRE_DX = 32;
    VILEFIRE_DY = 128;

    ItemAnim: array [0..ITEM_LAST] of record
      name: AnsiString;
      w, h: Integer;
      anim: TAnimInfo;
    end = (
      (name: 'NOTEXTURE';    w: 16; h: 16; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'MED1';         w: 16; h: 16; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'MED2';         w: 32; h: 32; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'BMED';         w: 32; h: 32; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'ARMORGREEN';   w: 32; h: 16; anim: (loop: true; delay: 20; frames: 3; back: true)),
      (name: 'ARMORBLUE';    w: 32; h: 16; anim: (loop: true; delay: 20; frames: 3; back: true)),
      (name: 'SBLUE';        w: 32; h: 32; anim: (loop: true; delay: 15; frames: 4; back: true)),
      (name: 'SWHITE';       w: 32; h: 32; anim: (loop: true; delay: 20; frames: 4; back: true)),
      (name: 'SUIT';         w: 32; h: 64; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'OXYGEN';       w: 16; h: 32; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'INVUL';        w: 32; h: 32; anim: (loop: true; delay: 20; frames: 4; back: true)),
      (name: 'SAW';          w: 64; h: 32; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'SHOTGUN1';     w: 64; h: 16; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'SHOTGUN2';     w: 64; h: 16; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'MGUN';         w: 64; h: 16; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'RLAUNCHER';    w: 64; h: 16; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'PGUN';         w: 64; h: 16; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'BFG';          w: 64; h: 64; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'SPULEMET';     w: 64; h: 16; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'CLIP';         w: 16; h: 16; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'AMMO';         w: 32; h: 16; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'SHELL1';       w: 16; h: 8;  anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'SHELL2';       w: 32; h: 16; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'ROCKET';       w: 16; h: 32; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'ROCKETS';      w: 64; h: 32; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'CELL';         w: 16; h: 16; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'CELL2';        w: 32; h: 32; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'BPACK';        w: 32; h: 32; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'KEYR';         w: 16; h: 16; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'KEYG';         w: 16; h: 16; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'KEYB';         w: 16; h: 16; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'KASTET';       w: 64; h: 32; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'PISTOL';       w: 64; h: 16; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'BOTTLE';       w: 16; h: 32; anim: (loop: true; delay: 20; frames: 4; back: true)),
      (name: 'HELMET';       w: 16; h: 16; anim: (loop: true; delay: 20; frames: 4; back: true)),
      (name: 'JETPACK';      w: 32; h: 32; anim: (loop: true; delay: 15; frames: 3; back: true)),
      (name: 'INVIS';        w: 32; h: 32; anim: (loop: true; delay: 20; frames: 4; back: true)),
      (name: 'FLAMETHROWER'; w: 64; h: 32; anim: (loop: true; delay: 1;  frames: 1; back: false)),
      (name: 'FUELCAN';      w: 16; h: 32; anim: (loop: true; delay: 1;  frames: 1; back: false))
    );

{$IFDEF ENABLE_GFX}
    GFXAnim: array [0..R_GFX_LAST] of record
      name: AnsiString;
      w, h: Integer;
      anim: TAnimInfo;
      rdelay: Integer;
      alpha: Integer;
    end = (
      (name: '';            w: 0;   h: 0;   anim: (loop: false; delay: 0; frames: 0;  back: false); rdelay: 0; alpha: 0),
      (name: 'TELEPORT';    w: 64;  h: 64;  anim: (loop: false; delay: 6; frames: 10; back: false); rdelay: 0; alpha: 0),
      (name: 'FLAME';       w: 32;  h: 32;  anim: (loop: false; delay: 3; frames: 11; back: false); rdelay: 0; alpha: 0),
      (name: 'EROCKET';     w: 128; h: 128; anim: (loop: false; delay: 6; frames: 6;  back: false); rdelay: 0; alpha: 0),
      (name: 'EBFG';        w: 128; h: 128; anim: (loop: false; delay: 6; frames: 6;  back: false); rdelay: 0; alpha: 0),
      (name: 'BFGHIT';      w: 64;  h: 64;  anim: (loop: false; delay: 4; frames: 4;  back: false); rdelay: 0; alpha: 0),
      (name: 'FIRE';        w: 64;  h: 128; anim: (loop: false; delay: 4; frames: 8;  back: false); rdelay: 2; alpha: 0),
      (name: 'ITEMRESPAWN'; w: 32;  h: 32;  anim: (loop: false; delay: 4; frames: 5;  back: true);  rdelay: 0; alpha: 0),
      (name: 'SMOKE';       w: 32;  h: 32;  anim: (loop: false; delay: 3; frames: 10; back: false); rdelay: 0; alpha: 0),
      (name: 'ESKELFIRE';   w: 64;  h: 64;  anim: (loop: false; delay: 8; frames: 3;  back: false); rdelay: 0; alpha: 0),
      (name: 'EPLASMA';     w: 32;  h: 32;  anim: (loop: false; delay: 3; frames: 4;  back: true);  rdelay: 0; alpha: 0),
      (name: 'EBSPFIRE';    w: 32;  h: 32;  anim: (loop: false; delay: 3; frames: 5;  back: false); rdelay: 0; alpha: 0),
      (name: 'EIMPFIRE';    w: 64;  h: 64;  anim: (loop: false; delay: 6; frames: 3;  back: false); rdelay: 0; alpha: 0),
      (name: 'ECACOFIRE';   w: 64;  h: 64;  anim: (loop: false; delay: 6; frames: 3;  back: false); rdelay: 0; alpha: 0),
      (name: 'EBARONFIRE';  w: 64;  h: 64;  anim: (loop: false; delay: 6; frames: 3;  back: false); rdelay: 0; alpha: 0),
      (name: 'TELEPORT';    w: 64;  h: 64;  anim: (loop: false; delay: 3; frames: 10; back: false); rdelay: 0; alpha: 0),   // fast
      (name: 'SMOKE';       w: 32;  h: 32;  anim: (loop: false; delay: 3; frames: 10; back: false); rdelay: 0; alpha: 150), // transparent
      (name: 'FLAME';       w: 32;  h: 32;  anim: (loop: false; delay: 3; frames: 11; back: false); rdelay: 2; alpha: 0)    // random
    );
{$ENDIF}

    ShotAnim: array [0..WEAPON_LAST] of record
      name: AnsiString;
      w, h: Integer;
      anim: TAnimInfo;
    end = (
      (name: '';            w: 0;  h: 0;  anim: (loop: true; delay: 0; frames: 0; back: false)),  // 0  KASTET
      (name: '';            w: 0;  h: 0;  anim: (loop: true; delay: 0; frames: 0; back: false)),  // 1  SAW
      (name: '';            w: 0;  h: 0;  anim: (loop: true; delay: 0; frames: 0; back: false)),  // 2  PISTOL
      (name: '';            w: 0;  h: 0;  anim: (loop: true; delay: 0; frames: 0; back: false)),  // 3  SHOTGUN1
      (name: '';            w: 0;  h: 0;  anim: (loop: true; delay: 0; frames: 0; back: false)),  // 4  SHOTGUN2
      (name: '';            w: 0;  h: 0;  anim: (loop: true; delay: 0; frames: 0; back: false)),  // 5  CHAINGUN
      (name: 'BROCKET';     w: 64; h: 32; anim: (loop: true; delay: 1; frames: 1; back: false)),  // 6  ROCKETLAUNCHER
      (name: 'BPLASMA';     w: 16; h: 16; anim: (loop: true; delay: 5; frames: 2; back: false)),  // 7  PLASMA
      (name: 'BBFG';        w: 64; h: 64; anim: (loop: true; delay: 6; frames: 2; back: false)),  // 8  BFG
      (name: '';            w: 0;  h: 0;  anim: (loop: true; delay: 0; frames: 0; back: false)),  // 9  SUPERPULEMET
      (name: 'FLAME';       w: 32; h: 32; anim: (loop: true; delay: 6; frames: 0{11}; back: false)), // 10 FLAMETHROWER
      (name: '';            w: 0;  h: 0;  anim: (loop: true; delay: 0; frames: 0; back: false)),  // 11
      (name: '';            w: 0;  h: 0;  anim: (loop: true; delay: 0; frames: 0; back: false)),  // 12
      (name: '';            w: 0;  h: 0;  anim: (loop: true; delay: 0; frames: 0; back: false)),  // 13
      (name: '';            w: 0;  h: 0;  anim: (loop: true; delay: 0; frames: 0; back: false)),  // 14
      (name: '';            w: 0;  h: 0;  anim: (loop: true; delay: 0; frames: 0; back: false)),  // 15
      (name: '';            w: 0;  h: 0;  anim: (loop: true; delay: 0; frames: 0; back: false)),  // 16
      (name: '';            w: 0;  h: 0;  anim: (loop: true; delay: 0; frames: 0; back: false)),  // 17
      (name: '';            w: 0;  h: 0;  anim: (loop: true; delay: 0; frames: 0; back: false)),  // 18
      (name: '';            w: 0;  h: 0;  anim: (loop: true; delay: 0; frames: 0; back: false)),  // 19
      (name: '';            w: 0;  h: 0;  anim: (loop: true; delay: 0; frames: 0; back: false)),  // 20 ZOMPY_PISTOL
      (name: 'BIMPFIRE';    w: 16; h: 16; anim: (loop: true; delay: 4; frames: 2; back: false)),  // 21 IMP_FIRE
      (name: 'BBSPFIRE';    w: 16; h: 16; anim: (loop: true; delay: 4; frames: 2; back: false)),  // 22 BSP_FIRE
      (name: 'BCACOFIRE';   w: 16; h: 16; anim: (loop: true; delay: 4; frames: 2; back: false)),  // 23 CACO_FIRE
      (name: 'BBARONFIRE';  w: 64; h: 16; anim: (loop: true; delay: 4; frames: 2; back: false)),  // 24 BARON_FIRE
      (name: 'BMANCUBFIRE'; w: 64; h: 32; anim: (loop: true; delay: 4; frames: 2; back: false)),  // 25 MANCUB_FIRE
      (name: 'BSKELFIRE';   w: 64; h: 64; anim: (loop: true; delay: 5; frames: 2; back: false))   // 26 SKEL_FIRE
    );

{$IFDEF ENABLE_SHELLS}
    ShellAnim: array [0..SHELL_LAST] of record
      name: AnsiString;
      dx, dy: Integer;
    end = (
      (name: 'EBULLET'; dx: 2; dy: 1), // 0 SHELL_BULLET
      (name: 'ESHELL';  dx: 4; dy: 2), // 1 SHELL_SHELL
      (name: 'ESHELL';  dx: 4; dy: 2)  // 2 SHELL_DBLSHELL
    );
{$ENDIF}

    PunchAnim: TAnimInfo = (loop: false; delay: 1; frames: 4; back: false);
    FlagAnim: TAnimInfo = (loop: true; delay: 8; frames: 5; back: false);
    VileFireAnim: TAnimInfo = (loop: true; delay:  2; frames: 8; back: false);

  type
    TBinHeapPanelDrawCmp = class
      public
        class function less (const a, b: TPanel): Boolean; inline;
    end;

    TBinHeapPanelDraw = specialize TBinaryHeapBase<TPanel, TBinHeapPanelDrawCmp>;

    TMonsterAnims = array [0..ANIM_LAST, TDirection] of TGLMultiTexture;

  var
    DebugCameraScale: Single;
    FillOutsizeArea: Boolean;
    SkyTexture: TGLTexture;
    RenTextures: array of record
      spec: LongInt;
      tex: TGLMultiTexture;
      anim: TAnimInfo;
    end;
    Items: array [0..ITEM_LAST] of record
      tex: TGLMultiTexture;
      frame: Integer;
    end;
    MonTextures: array [0..MONSTER_MAN] of TMonsterAnims;
    WeapTextures: array [0..WP_LAST, 0..W_POS_LAST, 0..W_ACT_LAST] of TGLTexture;
    ShotTextures: array [0..WEAPON_LAST] of TGLMultiTexture;
    FlagTextures: array [0..FLAG_LAST] of TGLMultiTexture;
    PunchTextures: array [Boolean, 0..2] of TGLMultiTexture; // [berserk, center/up/down]
    VileFire: TGLMultiTexture;
    InvulPenta: TGLTexture;
    IndicatorTexture: TGLTexture;
    TalkTexture: TGLTexture;
    Models: array of record
      anim: array [TDirection, 0..A_LAST] of record
        base, mask: TGLMultiTexture;
      end;
{$IFDEF ENABLE_GIBS}
      gibs: record
        base, mask: TGLTextureArray;
        rect: TRectArray;
      end;
{$ENDIF}
    end;

{$IFDEF ENABLE_SHELLS}
    ShellTextures: array [0..SHELL_LAST] of TGLTexture;
{$ENDIF}
{$IFDEF ENABLE_GFX}
    GFXTextures: array [0..R_GFX_LAST] of TGLMultiTexture;
    gfxlist: array of record
      typ: Byte;
      x, y: Integer;
      oldX, oldY: Integer;
      anim: TAnimInfo;
      time: LongWord;
      frame: LongInt;
    end = nil;
{$ENDIF}

    FlagFrame: LongInt;
    plist: TBinHeapPanelDraw = nil;

  class function TBinHeapPanelDrawCmp.less (const a, b: TPanel): Boolean; inline;
  begin
    if a.tag < b.tag then begin result := true; exit; end;
    if a.tag > b.tag then begin result := false; exit; end;
    result := a.arrIdx < b.arrIdx;
  end;

  procedure r_Map_Initialize;
  begin
    FlagFrame := 0;
    plist := TBinHeapPanelDraw.Create();
  end;

  procedure r_Map_Finalize;
  begin
    r_Common_FreeAndNil(plist);
    FlagFrame := 0;
  end;

  procedure r_Map_FreeModel (i: Integer);
    var a: Integer; d: TDirection;
  begin
    for d := TDirection.D_LEFT to TDirection.D_RIGHT do
    begin
      for a := A_STAND to A_LAST do
      begin
        r_Common_FreeAndNil(Models[i].anim[d, a].base);
        r_Common_FreeAndNil(Models[i].anim[d, a].mask);
      end;
    end;
    {$IFDEF ENABLE_GIBS}
      if Models[i].gibs.base <> nil then
        for a := 0 to High(Models[i].gibs.base) do
          r_Common_FreeAndNil(Models[i].gibs.base[a]);
      if Models[i].gibs.mask <> nil then
        for a := 0 to High(Models[i].gibs.mask) do
          r_Common_FreeAndNil(Models[i].gibs.mask[a]);
      Models[i].gibs.base := nil;
      Models[i].gibs.mask := nil;
      Models[i].gibs.rect := nil;
    {$ENDIF}
  end;

  procedure r_Map_LoadModel (i: Integer);
    var prefix: AnsiString; a: Integer; d: TDirection; m: ^TPlayerModelInfo;
  begin
    ASSERT(i < Length(Models));
    ASSERT(i < Length(PlayerModelsArray));
    r_Map_FreeModel(i);
    m := @PlayerModelsArray[i];
    prefix := m.FileName + ':TEXTURES/';
    for d := TDirection.D_LEFT to TDirection.D_RIGHT do
    begin
      for a := A_STAND to A_LAST do
      begin
        Models[i].anim[d, a].base := nil;
        Models[i].anim[d, a].mask := nil;
        if m.anim[d, a].resource <> '' then
          Models[i].anim[d, a].base := r_Textures_LoadMultiFromFileAndInfo(prefix + m.anim[d, a].resource, 64, 64, m.anim[d, a].frames, [TGLHints.txNoRepeat], true);
        if m.anim[d, a].mask <> '' then
          Models[i].anim[d, a].mask := r_Textures_LoadMultiFromFileAndInfo(prefix + m.anim[d, a].mask, 64, 64, m.anim[d, a].frames, [TGLHints.txNoRepeat], true);
      end
    end;
    {$IFDEF ENABLE_GIBS}
      Models[i].gibs.base := nil;
      Models[i].gibs.mask := nil;
      Models[i].gibs.rect := nil;
      if m.GibsCount > 0 then
      begin
        SetLength(Models[i].gibs.base, m.GibsCount);
        SetLength(Models[i].gibs.mask, m.GibsCount);
        SetLength(Models[i].gibs.rect, m.GibsCount);
        for a := 0 to m.GibsCount - 1 do
          Models[i].gibs.rect[a] := DefaultGibSize;
        if r_Textures_LoadStreamFromFile(prefix + m.GibsResource, 32, 32, m.GibsCount, m.GibsCount, Models[i].gibs.base, Models[i].gibs.rect, [TGLHints.txNoRepeat]) then
        begin
          if r_Textures_LoadStreamFromFile(prefix + m.GibsMask, 32, 32, m.GibsCount, m.GibsCount, Models[i].gibs.mask, nil, [TGLHints.txNoRepeat]) then
          begin
            // ok
          end;
        end;
      end;
    {$ENDIF}
  end;

  procedure r_Map_LoadMonsterAnim (m, a: Integer; d: TDirection);
    const dir: array [TDirection] of AnsiString = ('_L', '');
    var w, h, count: Integer;
  begin
    count := MONSTER_ANIMTABLE[m].AnimCount[a];
    if count > 0 then
    begin
      w := MTABLE[m].w;
      h := MTABLE[m].h;
      if (m = MONSTER_SOUL) and (a = ANIM_DIE) then
      begin
        // special case
        w := 128;
        h := 128;
      end;
      MonTextures[m, a, d] := r_Textures_LoadMultiFromFileAndInfo(
        GameWAD + ':MTEXTURES/' + MONSTERTABLE[m].name + '_' + ANIMTABLE[a].name + dir[d],
        w,
        h,
        count,
        [TGLHints.txNoRepeat],
        False
      );
    end
    else
      MonTextures[m, a, d] := nil;
  end;

  procedure r_Map_Load;
    const
      WeapName: array [0..WP_LAST] of AnsiString = ('', 'CSAW', 'HGUN', 'SG', 'SSG', 'MGUN', 'RKT', 'PLZ', 'BFG', 'SPL', 'FLM');
      WeapPos: array [0..W_POS_LAST] of AnsiString = ('', '_UP', '_DN');
      WeapAct: array [0..W_ACT_LAST] of AnsiString = ('', '_FIRE');
      PunchName: array [Boolean] of AnsiString = ('PUNCH', 'PUNCHB');
    var
      i, j, k: Integer; d: TDirection; b: Boolean;
  begin
    // --------- items --------- //
    r_Common_SetLoading(_lc[I_LOAD_ITEMS_DATA], ITEM_LAST + 1);
    for i := 0 to ITEM_LAST do
    begin
      Items[i].tex := r_Common_LoadTextureMultiFromFileAndInfo(
        GameWAD + ':TEXTURES/' + ItemAnim[i].name,
        ItemAnim[i].w,
        ItemAnim[i].h,
        ItemAnim[i].anim.frames,
        [TGLHints.txNoRepeat],
        false
      );
      Items[i].frame := 0;
    end;
    // --------- monsters --------- //
    r_Common_SetLoading(_lc[I_LOAD_MONSTER_TEXTURES], MONSTER_MAN - MONSTER_DEMON + 1);
    for i := MONSTER_DEMON to MONSTER_MAN do
    begin
      for j := 0 to ANIM_LAST do
        for d := TDirection.D_LEFT to TDirection.D_RIGHT do
          r_Map_LoadMonsterAnim(i, j, d);
      r_Common_StepLoading(1);
    end;
    VileFire := r_Textures_LoadMultiFromFileAndInfo(GameWAD + ':TEXTURES/FIRE', 64, 128, VileFireAnim.frames, [TGLHints.txNoRepeat]);
    // --------- player models --------- //
    if PlayerModelsArray <> nil then
    begin
      r_Common_SetLoading(_lc[I_LOAD_MODELS], Length(PlayerModelsArray));
      SetLength(Models, Length(PlayerModelsArray));
      for i := 0 to High(PlayerModelsArray) do
      begin
        r_Map_LoadModel(i);
        r_Common_StepLoading(1);
      end;
    end;
    // --------- player weapons --------- //
    r_Common_SetLoading(_lc[I_LOAD_WEAPONS_DATA], WP_LAST);
    for i := 1 to WP_LAST do
    begin
      for j := 0 to W_POS_LAST do
        for k := 0 to W_ACT_LAST do
          WeapTextures[i, j, k] := r_Textures_LoadFromFile(GameWAD + ':WEAPONS\' + WeapName[i] + WeapPos[j] + WeapAct[k], [TGLHints.txNoRepeat]);
      r_Common_StepLoading(1);
    end;
    // --------- gfx animations --------- //
    {$IFDEF ENABLE_GFX}
      r_Common_SetLoading('GFX Effects', R_GFX_LAST);
      for i := 1 to R_GFX_LAST do
      begin
        if GFXAnim[i].anim.frames > 0 then
          GFXTextures[i] := r_Common_LoadTextureMultiFromFileAndInfo(GameWad + ':TEXTURES/' + GFXAnim[i].name, GFXAnim[i].w, GFXAnim[i].h, GFXAnim[i].anim.frames, [TGLHints.txNoRepeat]);
      end;
    {$ENDIF}
    // --------- shots --------- //
    r_Common_SetLoading('Weapon splahses', WEAPON_LAST + 1);
    for i := 0 to WEAPON_LAST do
    begin
      if ShotAnim[i].anim.frames > 0 then
        ShotTextures[i] := r_Common_LoadTextureMultiFromFileAndInfo(GameWad + ':TEXTURES/' + ShotAnim[i].name, ShotAnim[i].w, ShotAnim[i].h, ShotAnim[i].anim.frames, [TGLHints.txNoRepeat]);
    end;
    // --------- flags --------- //
    r_Common_SetLoading('Flags', 2);
    FlagTextures[FLAG_NONE] := nil;
    FlagTextures[FLAG_RED]  := r_Common_LoadTextureMultiFromFileAndInfo(GameWad + ':TEXTURES/FLAGRED',  64, 64, 5, [TGLHints.txNoRepeat]);
    FlagTextures[FLAG_BLUE] := r_Common_LoadTextureMultiFromFileAndInfo(GameWad + ':TEXTURES/FLAGBLUE', 64, 64, 5, [TGLHints.txNoRepeat]);
    // FlagTextures[FLAG_DOM]  := r_Common_LoadTextureMultiFromFileAndInfo(GameWad + ':TEXTURES/FLAGDOM',  64, 64, 8, [TGLHints.txNoRepeat]);
    // --------- shells --------- //
    {$IFDEF ENABLE_SHELLS}
      r_Common_SetLoading('Shells', SHELL_LAST + 1);
      for i := 0 to SHELL_LAST do
        ShellTextures[i] := r_Common_LoadTextureFromFile(GameWad + ':TEXTURES/' + ShellAnim[i].name, [TGLHints.txNoRepeat]);
    {$ENDIF}
    // --------- other --------- //
    r_Common_SetLoading('Effects', 3 * 2 + 3);
    for b := false to true do
    begin
      for i := 0 to 2 do
        PunchTextures[b, i] := r_Common_LoadTextureMultiFromFileAndInfo(GameWad + ':WEAPONS/' + PunchName[b] + WeapPos[i], 64, 64, PunchAnim.frames, [TGLHints.txNoRepeat]);
    end;
    InvulPenta := r_Common_LoadTextureFromFile(GameWad + ':TEXTURES/PENTA', [TGLHints.txNoRepeat]);
    IndicatorTexture := r_Common_LoadTextureFromFile(GameWad + ':TEXTURES/PLRIND', [TGLHints.txNoRepeat]);
    TalkTexture := r_Common_LoadTextureFromFile(GameWad + ':TEXTURES/TALKBUBBLE', [TGLHints.txNoRepeat]);
  end;

  procedure r_Map_Free;
    var i, j, k: Integer; d: TDirection; b: Boolean;
  begin
    r_Common_FreeAndNil(TalkTexture);
    r_Common_FreeAndNil(IndicatorTexture);
    r_Common_FreeAndNil(InvulPenta);
    for b := false to true do
      for i := 0 to 2 do
        r_Common_FreeAndNil(PunchTextures[b, i]);
    {$IFDEF ENABLE_SHELLS}
      for i := 0 to SHELL_LAST do
        r_Common_FreeAndNil(ShellTextures[i]);
    {$ENDIF}
    for i := 0 to FLAG_LAST do
      r_Common_FreeAndNil(FlagTextures[i]);
    for i := 0 to WEAPON_LAST do
      r_Common_FreeAndNil(ShotTextures[i]);
    {$IFDEF ENABLE_GFX}
      SetLength(gfxlist, 0);
      for i := 0 to R_GFX_LAST do
        r_Common_FreeAndNil(GFXTextures[i]);
    {$ENDIF}
    for i := 1 to WP_LAST do
      for j := 0 to W_POS_LAST do
        for k := 0 to W_ACT_LAST do
          r_Common_FreeAndNil(WeapTextures[i, j, k]);
    if Models <> nil then
      for i := 0 to High(Models) do
        r_Map_FreeModel(i);
    for i := MONSTER_DEMON to MONSTER_MAN do
      for j := 0 to ANIM_LAST do
        for d := TDirection.D_LEFT to TDirection.D_RIGHT do
          r_Common_FreeAndNil(MonTextures[i, j, d]);
    for i := 0 to ITEM_LAST do
      r_Common_FreeAndNil(Items[i].tex);
  end;

  procedure r_Map_LoadTextures;
    const DefaultAnimInfo: TAnimInfo = (loop: true; delay: 1; frames: 1; back: false);
    var i, n: Integer; txt: TAnimTextInfo;
  begin
    if Textures <> nil then
    begin
      n := Length(Textures);
      SetLength(RenTextures, n);
      r_Common_SetLoading(_lc[I_LOAD_TEXTURES], n);
      for i := 0 to n - 1 do
      begin
        txt.anim := DefaultAnimInfo;
        RenTextures[i].tex := nil;
        case Textures[i].TextureName of
          TEXTURE_NAME_WATER: RenTextures[i].spec := TEXTURE_SPECIAL_WATER;
          TEXTURE_NAME_ACID1: RenTextures[i].spec := TEXTURE_SPECIAL_ACID1;
          TEXTURE_NAME_ACID2: RenTextures[i].spec := TEXTURE_SPECIAL_ACID2;
          else
            RenTextures[i].spec := 0;
            RenTextures[i].tex := r_Textures_LoadMultiTextFromFile(Textures[i].FullName, txt, []);
            if RenTextures[i].tex = nil then
              e_LogWritefln('r_Map_LoadTextures: failed to load texture: %s', [Textures[i].FullName])
            else
              r_Common_StepLoading(1);
        end;
        RenTextures[i].anim := txt.anim;
      end;
    end;
    if gMapInfo.SkyFullName <> '' then
    begin
      r_Common_SetLoading(_lc[I_LOAD_SKY], 1);
      SkyTexture := r_Common_LoadTextureFromFile(gMapInfo.SkyFullName, [TGLHints.txNoRepeat]);
    end;
    plist.Clear;
  end;

  procedure r_Map_FreeTextures;
    var i: Integer;
  begin
    plist.Clear;
    r_Common_FreeAndNil(SkyTexture);
    if RenTextures <> nil then
      for i := 0 to High(RenTextures) do
        r_Common_FreeAndNil(RenTextures[i].tex);
    SetLength(RenTextures, 0);
  end;

  procedure r_Map_DrawPanel (p: TPanel);
    var Texture: Integer; t: TGLMultiTexture; tex: TGLTexture; count, frame: LongInt; a: TAnimInfo;
  begin
    ASSERT(p <> nil);
    if p.FCurTexture >= 0 then
    begin
      Texture := p.TextureIDs[p.FCurTexture].Texture;
      t := RenTextures[Texture].tex;
      if (RenTextures[Texture].spec = 0) or (t <> nil) then
      begin
        count := 0; frame := 0;
        if p.AnimTime <= gTime then
        begin
          a := RenTextures[Texture].anim;
          a.loop := p.AnimLoop;
          g_Anim_GetFrameByTime(a, (gTime - p.AnimTime) DIV GAME_TICK, count, frame);
        end;
        if t <> nil then
        begin
          tex := t.GetTexture(frame);
          r_Draw_TextureRepeat(tex, p.x, p.y, p.width, p.height, false, 255, 255, 255, 255 - p.alpha, p.blending);
        end
        else
          r_Draw_TextureRepeat(nil, p.x, p.y, p.width, p.height, false, 255, 255, 255, 255, false);
      end;

      if t = nil then
      begin
        case RenTextures[Texture].spec of
          TEXTURE_SPECIAL_WATER: r_Draw_Filter(p.x, p.y, p.x + p.width, p.y + p.height, 0, 0, 255, 255);
          TEXTURE_SPECIAL_ACID1: r_Draw_Filter(p.x, p.y, p.x + p.width, p.y + p.height, 0, 230, 0, 255);
          TEXTURE_SPECIAL_ACID2: r_Draw_Filter(p.x, p.y, p.x + p.width, p.y + p.height, 230, 0, 0, 255);
        end
      end
    end
  end;

  procedure r_Map_DrawPanelType (panelTyp: DWORD);
    var tagMask, i: Integer; p: TPanel;
  begin
    i := 0;
    tagMask := PanelTypeToTag(panelTyp);
    while plist.count > 0 do
    begin
      p := TPanel(plist.Front());
      if (p.tag and tagMask) = 0 then
        break;
      r_Map_DrawPanel(p);
      Inc(i);
      plist.PopFront
    end;
  end;

  procedure r_Map_DrawItems (x, y, w, h: Integer; drop: Boolean);
    var i, xx, yy: Integer; it: PItem; t: TGLMultiTexture; tex: TGLTexture;
  begin
    if ggItems <> nil then
    begin
      for i := 0 to High(ggItems) do
      begin
        it := @ggItems[i];
        if it.used and it.alive and (it.dropped = drop) and (it.ItemType > ITEM_NONE) and (it.ItemType <= ITEM_LAST) then
        begin
          t := Items[it.ItemType].tex;
          if g_Collide(it.obj.x, it.obj.y, t.width, t.height, x, y, w, h) then
          begin
            r_Common_GetObjectPos(it.obj, xx, yy);
            tex := t.GetTexture(Items[it.ItemType].frame);
            r_Draw_TextureRepeat(tex, xx, yy, tex.width, tex.height, false, 255, 255, 255, 255, false);
          end;
        end;
      end;
    end;
    // TODO draw g_debug_frames
  end;

  function r_Map_GetMonsterTexture (m, a: Integer; d: TDirection; out t: TGLMultiTexture; out dx, dy: Integer; out flip: Boolean): Boolean;
    // var c: Integer;
  begin
    t := nil; dx := 0; dy := 0; flip := false;
    result := MonTextures[m, a, d] <> nil;
    if result = false then
    begin
      flip := true;
      if d = TDirection.D_RIGHT then d := TDirection.D_LEFT else d := TDirection.D_RIGHT;
      result := MonTextures[m, a, d] <> nil;
    end;
    if result = true then
    begin
      t := MonTextures[m, a, d];
      if d = TDirection.D_LEFT then
      begin
        dx := MONSTER_ANIMTABLE[m].AnimDeltaLeft[a].X;
        dy := MONSTER_ANIMTABLE[m].AnimDeltaLeft[a].Y;
      end
      else
      begin
        dx := MONSTER_ANIMTABLE[m].AnimDeltaRight[a].X;
        dy := MONSTER_ANIMTABLE[m].AnimDeltaRight[a].Y;
      end;
      if flip then
      begin
//        c := (MONSTERTABLE[MonsterType].Rect.X - dx) + MONSTERTABLE[MonsterType].Rect.Width;
//        dx := MTABLE[m].width - c - MONSTERTABLE[MonsterType].Rect.X;
        dx := -dx;
      end;
    end;
  end;

  procedure r_Map_DrawMonsterAttack (constref mon: TMonster);
    var o: TObj; count, frame, xx, yy: LongInt; tex: TGLTexture;
  begin
    if VileFire <> nil then
    begin
      if (mon.MonsterType = MONSTER_VILE) and (mon.MonsterState = MONSTATE_SHOOT) and (mon.VileFireTime <= gTime) then
      begin
        if r_Common_GetPosByUID(mon.MonsterTargetUID, o, xx, yy) then
        begin
          g_Anim_GetFrameByTime(VileFireAnim, (gTime - mon.VileFireTime) DIV GAME_TICK, count, frame);
          tex := VileFire.GetTexture(frame);
          r_Draw_TextureRepeat(tex, xx + o.rect.x + (o.rect.width div 2) - VILEFIRE_DX, yy + o.rect.y + o.rect.height - VILEFIRE_DY, tex.width, tex.height, False, 255, 255, 255, 255, false);
        end;
      end;
    end;
  end;

  procedure r_Map_DrawMonster (constref mon: TMonster);
    var m, a, xx, yy, dx, dy: Integer; d: TDirection; flip: Boolean; t: TGLMultiTexture;
  begin
    m := mon.MonsterType;
    a := mon.MonsterAnim;
    d := mon.GameDirection;

    if r_Map_GetMonsterTexture(m, a, d, t, dx, dy, flip) then
    begin
      r_Common_GetObjectPos(mon.obj, xx, yy);
      r_Draw_MultiTextureRepeat(t, mon.DirAnim[a, d], false, xx + dx, yy + dy, t.width, t.height, flip, 255, 255, 255, 255, false);
    end;

    // TODO draw g_debug_frames
  end;

  procedure r_Map_DrawMonsters (x, y, w, h: Integer);
    var i: Integer; m: TMonster;
  begin
    if gMonsters <> nil then
    begin
      for i := 0 to High(gMonsters) do
      begin
        m := gMonsters[i];
        if m <> nil then
        begin
          r_Map_DrawMonsterAttack(m);
          // TODO select from grid
          if g_Collide(m.obj.x + m.obj.rect.x, m.obj.y + m.obj.rect.y, m.obj.rect.width, m.obj.rect.height, x, y, w, h) then
            r_Map_DrawMonster(m);
        end;
      end;
    end;
  end;

  function r_Map_GetPlayerModelTex (i: Integer; var a: Integer; var d: TDirection; out flip: Boolean): Boolean;
  begin
    flip := false;
    result := Models[i].anim[d, a].base <> nil;
    if result = false then
    begin
      flip := true;
      if d = TDirection.D_LEFT then d := TDirection.D_RIGHT else d := TDirection.D_LEFT;
      result := Models[i].anim[d, a].base <> nil;
    end;
  end;

  procedure r_Map_DrawPlayerModel (pm: TPlayerModel; x, y: Integer; alpha: Byte);
    var a, pos, act, xx, yy, angle: Integer; d: TDirection; flip, back: Boolean; t: TGLMultiTexture; tex: TGLTexture; c: TRGB;
  begin
    a := pm.CurrentAnimation;
    d := pm.Direction;

    (* draw flag*)
    t := FlagTextures[pm.Flag];
    if (t <> nil) and not (a in [A_DIE1, A_DIE2])  then
    begin
      flip := d = TDirection.D_RIGHT;
      angle := PlayerModelsArray[pm.id].FlagAngle;
      xx := PlayerModelsArray[pm.id].FlagPoint.X;
      yy := PlayerModelsArray[pm.id].FlagPoint.Y;
      tex := t.GetTexture(FlagFrame);
      r_Draw_TextureRepeatRotate(
        tex,
        x + IfThen(flip, 2 * FLAG_BASEPOINT.X - xx + 1, xx - 1) - FLAG_BASEPOINT.X,
        y + yy - FLAG_BASEPOINT.Y + 1,
        tex.width,
        tex.height,
        flip,
        255, 255, 255, 255, false,
        IfThen(flip, 64 - FLAG_BASEPOINT.X, FLAG_BASEPOINT.X),
        FLAG_BASEPOINT.Y,
        IfThen(flip, angle, -angle)
      );
    end;

    (* draw weapon *)
    if PlayerModelsArray[pm.id].HaveWeapon and not (a in [A_DIE1, A_DIE2, A_PAIN]) then
    begin
      case a of
        A_SEEUP, A_ATTACKUP: pos := W_POS_UP;
        A_SEEDOWN, A_ATTACKDOWN: pos := W_POS_DOWN;
      else pos := W_POS_NORMAL;
      end;
      if (a in [A_ATTACK, A_ATTACKUP, A_ATTACKDOWN]) or pm.GetFire() then
        act := W_ACT_FIRE
      else
        act := W_ACT_NORMAL;
      tex := WeapTextures[pm.CurrentWeapon, pos, act];
      if tex <> nil then
      begin
        xx := PlayerModelsArray[pm.id].WeaponPoints[pm.CurrentWeapon, a, d, pm.AnimState.CurrentFrame].X;
        yy := PlayerModelsArray[pm.id].WeaponPoints[pm.CurrentWeapon, a, d, pm.AnimState.CurrentFrame].Y;
        r_Draw_Texture(
          tex,
          x + xx,
          y + yy,
          tex.width,
          tex.height,
          d = TDirection.D_LEFT,
          255, 255, 255, alpha, false
        );
      end;
    end;

    (* draw body *)
    if r_Map_GetPlayerModelTex(pm.id, a, d, flip) then
    begin
      t := Models[pm.id].anim[d, a].base;
      back := PlayerModelsArray[pm.id].anim[d, a].back;
      r_Draw_MultiTextureRepeat(t, pm.AnimState, back, x, y, t.width, t.height, flip, 255, 255, 255, alpha, false);
      t := Models[pm.id].anim[d, a].mask;
      if t <> nil then
      begin
        c := pm.Color;
        r_Draw_MultiTextureRepeat(t, pm.AnimState, back, x, y, t.width, t.height, flip, c.r, c.g, c.b, alpha, false);
      end;
    end;
  end;

  procedure r_Map_DrawBubble (x, y: Integer; cb, cf: TRGB);
    var dot: Integer;
  begin
    // Outer borders
    r_Draw_Rect(x + 1, y,     x + 18, y + 13, cb.R, cb.G, cb.B, 255);
    r_Draw_Rect(x,     y + 1, x + 19, y + 12, cb.R, cb.G, cb.B, 255);
    // Inner box
    r_Draw_FillRect(x + 1, y + 1, x + 18, y + 12, cf.R, cf.G, cf.B, 255);
    // TODO Tail
    // Dots
    dot := 6;
    r_Draw_FillRect(x + dot + 0, y + 8, x + dot + 0 + 1 + 1, y + 9 + 1, cb.R, cb.G, cb.B, 255);
    r_Draw_FillRect(x + dot + 3, y + 8, x + dot + 3 + 1 + 1, y + 9 + 1, cb.R, cb.G, cb.B, 255);
    r_Draw_FillRect(x + dot + 6, y + 8, x + dot + 6 + 1 + 1, y + 9 + 1, cb.R, cb.G, cb.B, 255);
  end;

  procedure r_Map_DrawTalkBubble (p: TPlayer);
    var xx, yy, x, y: Integer; cb, cf: TRGB;
  begin
    r_Common_GetPlayerPos(p, xx, yy);
    x := xx + p.obj.rect.x + p.obj.rect.width div 2;
    y := yy;
    cb := _RGB(63, 63, 63);
    cf := _RGB(240, 240, 240);
    case gChatBubble of
      1: // simple text
      begin
        r_Common_DrawText('[...]', x, y, 255, 255, 255, 255, stdfont, TBasePoint.BP_DOWN);
      end;
      2: // adv team color
      begin
        case p.Team of
          TEAM_RED:  cb := _RGB(255, 63, 63);
          TEAM_BLUE: cb := _RGB(63, 63, 255);
        end;
        r_Map_DrawBubble(x, y - 18, cb, cf);
      end;
      3: // adv player color
      begin
        cb := p.Model.Color;
        cf.R := MIN(cb.R * 2 + 64, 255);
        cf.G := MIN(cb.G * 2 + 64, 255);
        cf.B := MIN(cb.B * 2 + 64, 255);
        if (ABS(cf.R - cb.R) < 32) or (ABS(cf.G - cb.G) < 32) or (ABS(cf.B - cb.B) < 32) then
        begin
          cb.R := MAX(cf.R div 2 - 16, 0);
          cb.G := MAX(cf.G div 2 - 16, 0);
          cb.B := MAX(cf.B div 2 - 16, 0);
        end;
        r_Map_DrawBubble(x, y - 18, cb, cf);
      end;
      4: // textured
      if TalkTexture <> nil then
      begin
        r_Common_DrawTexture(TalkTexture, x + 5, y, TalkTexture.width, TalkTexture.height, TBasePoint.BP_DOWN);
      end;
    end;
  end;

  procedure r_Map_DrawPlayer (p, drawed: TPlayer);
    var x, y, ax, ay, w, h: Integer; b, flip: Boolean; t: TGLMultiTexture; tex: TGLTexture; alpha: Byte; count, frame: LongInt;
  begin
    if p.alive then
    begin
      r_Common_GetPlayerPos(p, x, y);

      (* punch effect *)
      if p.PunchTime <= gTime then
      begin
        g_Anim_GetFrameByTime(PunchAnim, (gTime - p.PunchTime) DIV GAME_TICK, count, frame);
        if count < 1 then
        begin
          b := R_BERSERK in p.FRulez;
          if p.FKeys[KEY_DOWN].pressed then
            t := PunchTextures[b, 2]
          else if p.FKeys[KEY_UP].pressed then
            t := PunchTextures[b, 1]
          else
            t := PunchTextures[b, 0];
          if t <> nil then
          begin
            flip := p.Direction = TDirection.D_LEFT;
            ax := IfThen(flip, 15 - p.Obj.Rect.X, p.Obj.Rect.X - 15); // ???
            ay := p.Obj.Rect.Y - 11;
            tex := t.GetTexture(frame);
            r_Draw_TextureRepeat(tex, x + ax, y + ay, tex.width, tex.height, flip, 255, 255, 255, 255, false)
          end;
        end;
      end;

      (* invulnerability effect *)
      if (InvulPenta <> nil) and (p.FMegaRulez[MR_INVUL] > gTime) and ((p <> drawed) or (p.SpawnInvul >= gTime)) then
      begin
        w := InvulPenta.width;
        h := InvulPenta.height;
        ax := p.Obj.Rect.X + (p.Obj.Rect.Width div 2) - (w div 2); // + IfThen(flip, +4, -2) // ???
        ay := p.Obj.Rect.Y + (p.Obj.Rect.Height div 2) - (h div 2) - 7; // ???
        r_Draw_Texture(InvulPenta, x + ax, y + ay, w, h, false, 255, 255, 255, 255, false);
      end;

      (* invisibility effect *)
      alpha := 255;
      if p.FMegaRulez[MR_INVIS] > gTime then
      begin
        if (drawed <> nil) and ((p = drawed) or ((p.Team = drawed.Team) and (gGameSettings.GameMode <> GM_DM))) then
        begin
          if (p.FMegaRulez[MR_INVIS] - gTime > 2100) or not ODD((p.FMegaRulez[MR_INVIS] - gTime) div 300) then
            alpha := 55;
        end
        else
          alpha := 1; // ???
      end;

      r_Map_DrawPlayerModel(p.Model, x, y, alpha);
    end;
    // TODO draw g_debug_frames

    if (gChatBubble > 0) and p.FKeys[KEY_CHAT].Pressed and (p.Ghost = false) then
      if (p.FMegaRulez[MR_INVIS] <= gTime) or ((drawed <> nil) and ((p = drawed) or (p.Team = drawed.Team) and (gGameSettings.GameMode <> GM_DM))) then
        r_Map_DrawTalkBubble(p);

    // TODO draw aim
  end;

  procedure r_Map_DrawPlayers (x, y, w, h: Integer; player: TPlayer);
    var i: Integer;
  begin
    if gPlayers <> nil then
      for i := 0 to High(gPlayers) do
        if gPlayers[i] <> nil then
          r_Map_DrawPlayer(gPlayers[i], player);
  end;

{$IFDEF ENABLE_GIBS}
  function r_Map_GetGibSize (m, i: Integer): TRectWH;
  begin
    result := Models[m].gibs.rect[i];
  end;

  procedure r_Map_DrawGibs (x, y, w, h: Integer);
    var i, xx, yy, m, id, rx, ry, ra: Integer; p: PObj; t: TGLTexture;
  begin
    if gGibs <> nil then
    begin
      for i := 0 to High(gGibs) do
      begin
        if gGibs[i].alive then
        begin
          p := @gGibs[i].Obj;
          if g_Obj_Collide(x, y, w, h, p) then
          begin
            r_Common_GetObjectPos(p^, xx, yy);
            id := gGibs[i].GibID;
            m := gGibs[i].ModelID;
            t := Models[m].gibs.base[id];
            if t <> nil then
            begin
              rx := p.Rect.X + p.Rect.Width div 2;
              ry := p.Rect.Y + p.Rect.Height div 2;
              ra := gGibs[i].RAngle;
              r_Draw_TextureRepeatRotate(t, xx, yy, t.width, t.height, false, 255, 255, 255, 255, false, rx, ry, ra);
              t := Models[m].gibs.mask[id];
              if t <> nil then
                r_Draw_TextureRepeatRotate(t, xx, yy, t.width, t.height, false, gGibs[i].Color.R, gGibs[i].Color.G, gGibs[i].Color.B, 255, false, rx, ry, ra);
              // r_Draw_TextureRepeatRotate(nil, xx + p.Rect.X, yy + p.Rect.Y, p.Rect.Width, p.Rect.Height, false, 255, 255, 255, 255, false, p.Rect.Width div 2, p.Rect.Height div 2, ra);
            end;
          end;
        end;
      end;
    end;
    // TODO draw g_debug_frames
  end;
{$ENDIF}

{$IFDEF ENABLE_CORPSES}
  procedure r_Map_DrawCorpses (x, y, w, h: Integer);
    var i, xx, yy: Integer; p: TCorpse;
  begin
    if gCorpses <> nil then
    begin
      for i := 0 to High(gCorpses) do
      begin
        p := gCorpses[i];
        if (p <> nil) and (p.state <> CORPSE_STATE_REMOVEME) and (p.model <> nil) then
        begin
          r_Common_GetObjectPos(p.obj, xx, yy);
          r_Map_DrawPlayerModel(p.model, xx, yy, 255);
        end;
      end;
    end;
    // TODO draw g_debug_frames
  end;
{$ENDIF}

{$IFDEF ENABLE_GFX}
  function r_Map_GetGFXID (): Integer;
    var i: Integer;
  begin
    i := 0;
    if gfxlist <> nil then
    begin
      while (i < Length(gfxlist)) and (gfxlist[i].typ > 0) do
        Inc(i);
      if i >= Length(gfxlist) then
        SetLength(gfxlist, Length(gfxlist) + 1)
    end
    else
      SetLength(gfxlist, 1);
    gfxlist[i].typ := R_GFX_NONE;
    result := i
  end;

  procedure r_Map_NewGFX (typ, x, y: Integer);
    var i: Integer;
  begin
    if gpart_dbg_enabled and (typ > 0) and (typ <= R_GFX_LAST) then
    begin
      i := r_Map_GetGFXID();
      if i >= 0 then
      begin
        gfxlist[i].typ := typ;
        gfxlist[i].x := x;
        gfxlist[i].y := y;
        gfxlist[i].oldX := x;
        gfxlist[i].oldY := y;
        gfxlist[i].anim := GFXAnim[typ].anim;
        gfxlist[i].time := gTime DIV GAME_TICK;
        gfxlist[i].frame := 0;
        INC(gfxlist[i].anim.delay, Random(GFXAnim[typ].rdelay));
      end;
    end;
  end;

  procedure r_Map_UpdateGFX (tick: LongWord);
    var i: Integer; count: LongInt;
  begin
    if gfxlist <> nil then
    begin
      for i := 0 to High(gfxlist) do
      begin
        if (gfxlist[i].typ > 0) and (tick >= gfxlist[i].time) then
        begin
          g_Anim_GetFrameByTime(gfxlist[i].anim, tick - gfxlist[i].time, count, gfxlist[i].frame);
          if count < 1 then
          begin
            gfxlist[i].oldX := gfxlist[i].x;
            gfxlist[i].oldY := gfxlist[i].y;
            case gfxlist[i].typ of
              R_GFX_FLAME, R_GFX_SMOKE:
              begin
                if Random(3) = 0 then
                  gfxlist[i].x := gfxlist[i].x - 1 + Random(3);
                if Random(2) = 0 then
                  gfxlist[i].y := gfxlist[i].y - Random(2);
              end;
            end;
          end
          else
            gfxlist[i].typ := R_GFX_NONE;
        end;
      end;
    end;
  end;

  procedure r_Map_DrawGFX (x, y, w, h: Integer);
    var i, fx, fy, typ: Integer; t: TGLMultiTexture; tex: TGLTexture;
  begin
    if gfxlist <> nil then
    begin
      for i := 0 to High(gfxlist) do
      begin
        if gfxlist[i].typ > 0 then
        begin
          typ := gfxlist[i].typ;
          t := GFXTextures[typ];
          if t <> nil then
          begin
            fx := nlerp(gfxlist[i].oldX, gfxlist[i].x, gLerpFactor);
            fy := nlerp(gfxlist[i].oldY, gfxlist[i].y, gLerpFactor);
            tex := t.GetTexture(gfxlist[i].frame);
            r_Draw_TextureRepeat(tex, fx, fy, tex.width, tex.height, false, 255, 255, 255, 255 - GFXAnim[typ].alpha, false);
          end;
        end;
      end;
    end;
  end;

  procedure r_Map_DrawParticles (x, y, w, h: Integer);
    var i, fx, fy: Integer;
  begin
    if gpart_dbg_enabled and (Particles <> nil) then
    begin
      r_Draw_EnableTexture2D(false);
      if (g_dbg_scale < 0.6) then
        glPointSize(1)
      else if (g_dbg_scale > 1.3) then
        glPointSize(g_dbg_scale + 1)
      else
        glPointSize(2);
      glDisable(GL_POINT_SMOOTH);
      glEnable(GL_BLEND);
      glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

      r_Draw_SetColor(255, 255, 255, 255);
      glBegin(GL_POINTS);
        for i := 0 to High(Particles) do
        begin
          if Particles[i].alive then
          begin
            fx := nlerp(Particles[i].oldX, Particles[i].x, gLerpFactor);
            fy := nlerp(Particles[i].oldY, Particles[i].y, gLerpFactor);
            glColor4ub(Particles[i].red, Particles[i].green, Particles[i].blue, Particles[i].alpha);
            glVertex2i(fx, fy);
          end;
        end;
      glEnd;
      r_Draw_SetColor(0, 0, 0, 255);

      glDisable(GL_BLEND);
    end;
  end;
{$ENDIF}

  procedure r_Map_DrawShots (x, y, w, h: Integer);
    var i, a, xx, yy, pX, pY, typ: Integer; count, frame: LongInt; t: TGLMultiTexture; tex: TGLTexture;
  begin
    if Shots <> nil then
    begin
      for i := 0 to High(Shots) do
      begin
        typ := Shots[i].ShotType;
        if typ <> 0 then
        begin
          t := ShotTextures[typ];
          if t <> nil then
          begin
            a := 0;
            case typ of
              WEAPON_ROCKETLAUNCHER, WEAPON_BARON_FIRE, WEAPON_MANCUB_FIRE, WEAPON_SKEL_FIRE:
                a := -GetAngle2(Shots[i].Obj.Vel.X, Shots[i].Obj.Vel.Y)
            end;
            r_Common_GetObjectPos(Shots[i].Obj, xx, yy);
            pX := Shots[i].Obj.Rect.Width div 2;
            pY := Shots[i].Obj.Rect.Height div 2;
            g_Anim_GetFrameByTime(ShotAnim[typ].anim, (gTime - Shots[i].time) DIV GAME_TICK, count, frame);
            tex := t.GetTexture(frame);
            r_Draw_TextureRepeatRotate(tex, xx, yy, tex.width, tex.height, false, 255, 255, 255, 255, false, pX, pY, a);
          end;
        end;
      end;
    end;
    // TODO draw g_debug_frames
  end;

  procedure r_Map_DrawFlags (x, y, w, h: Integer);
    var i, dx, xx, yy: Integer; flip: Boolean; t: TGLMultiTexture; tex: TGLTexture;
  begin
    if gGameSettings.GameMode = GM_CTF then
    begin
      for i := FLAG_RED to FLAG_BLUE do
      begin
        if not (gFlags[i].state in [FLAG_STATE_NONE, FLAG_STATE_CAPTURED]) then
        begin
          r_Common_GetObjectPos(gFlags[i].Obj, xx, yy);
          flip := gFlags[i].Direction = TDirection.D_LEFT;
          if flip then dx := -1 else dx := +1;
          t := FlagTextures[i];
          tex := t.GetTexture(FlagFrame);
          r_Draw_TextureRepeat(tex, xx + dx, yy + 1, tex.width, tex.height, flip, 255, 255, 255, 255, false)
        end;
      end;
    end;
    // TODO g_debug_frames
  end;

{$IFDEF ENABLE_SHELLS}
  procedure r_Map_DrawShells (x, y, w, h: Integer);
    var i, xx, yy, typ: Integer; t: TGLTexture; p: PObj;
  begin
    if gShells <> nil then
    begin
      for i := 0 to High(gShells) do
      begin
        if gShells[i].alive then
        begin
          typ := gShells[i].SType;
          if typ <= SHELL_LAST then
          begin
            p := @gShells[i].Obj;
            if g_Obj_Collide(x, y, w, h, p) then
            begin
              t := ShellTextures[typ];
              if t <> nil then
              begin
                r_Common_GetObjectPos(p^, xx, yy);
                r_Draw_TextureRepeatRotate(t, xx, yy, t.width, t.height, false, 255, 255, 255, 255, false, ShellAnim[typ].dx, ShellAnim[typ].dy, gShells[i].RAngle);
              end;
            end;
          end;
        end;
      end;
    end;
  end;
{$ENDIF}

  procedure r_Map_CalcSkyParallax (cx, cy, vw, vh, sw, sh, mw, mh: LongInt; out x, y, w, h: LongInt);
    const
      factor = 120; (* size ratio between view and sky (120%) *)
      limit = 100;  (* max speed for parallax *)
    var
      msw, msh, mvw, mvh, svw, svh: LongInt;
  begin
    msw := vw * factor div 100;
    msh := vh * factor div 100;
    r_Common_CalcAspect(sw, sh, msw, msh, (sw / sh) <= (msw / msh), w, h);

    (* calc x parallax or sky center on speed limit *)
    mvw := MAX(1, mw - vw);
    svw := w - vw;
    if 100 * svw div mvw <= limit then
      x := -cx * svw div mvw
    else
      x := -svw div 2;

    (* calc y parallax or sky center on speed limit *)
    mvh := MAX(1, mh - vh);
    svh := h - vh;
    if 100 * svh div mvh <= limit then
      y := -cy * svh div mvh
    else
      y := -svh div 2;

    (* handle out of map bounds *)
    if x > 0 then x := 0;
    if y > 0 then y := 0;
    if x < -svw then x := -svw;
    if y < -svh then y := -svh;
  end;

  procedure r_Map_DrawScreenEffect (x, y, w, h, level: Integer; r, g, b: Byte);
    var i: Integer;
  begin
    if level > 0 then
    begin
      case level of
        0..14: i := 0;
        15..34: i := 1;
        35..54: i := 2;
        55..74: i := 3;
        75..94: i := 4;
      else i := 5
      end;
      r_Draw_FillRect(x, y, x + w, y + h, r, g, b, i * 50)
    end;
  end;

  procedure r_Map_DrawScreenEffects (x, y, w, h: Integer; p: TPlayer);
  begin
    if p <> nil then
    begin
      r_Map_DrawScreenEffect(x, y, w, h, p.pain, 255, 0, 0);
      r_Map_DrawScreenEffect(x, y, w, h, p.pickup, 150, 200, 150);
      if (p.FMegaRulez[MR_INVUL] >= gTime) and (p.SpawnInvul < gTime) then
      begin
        if ((p.FMegaRulez[MR_INVUL] - gTime) > 2100) or not ODD((p.FMegaRulez[MR_INVUL] - gTime) div 300) then
          r_Draw_InvertRect(x, y, x + w, y + h, 191, 191, 191, 255);
      end;
      if p.FMegaRulez[MR_SUIT] >= gTime then
      begin
        if ((p.FMegaRulez[MR_SUIT] - gTime) > 2100) or not ODD((p.FMegaRulez[MR_SUIT] - gTime) div 300) then
          r_Draw_FillRect(x, y, x + w, y + h, 0, 96, 0, 55);
      end;
      if (p.Berserk >= 0) and (p.Berserk >= gTime) and (gFlash = 2) then
      begin
        r_Draw_FillRect(x, y, x + w, y + h, 255, 0, 0, 55);
      end;
    end;
  end;

  procedure r_Map_DrawIndicator (p: TPlayer; color: TRGB; cx, cy, cw, ch: Integer);
    var a, ax, ay, fx, fy, xx, yy: Integer;
  begin
    if (p <> nil) and p.Alive and (p.Spectator = false) then
    begin
      r_Common_GetPlayerPos(p, fx, fy);
      case gPlayerIndicatorStyle of
        0:
        if IndicatorTexture <> nil then
        begin
          ax := IndicatorTexture.width div 2;
          ay := IndicatorTexture.height div 2;
          if (p.obj.x + p.obj.rect.x) < cx then
          begin
            a := 90;
            xx := fx + p.obj.rect.x + p.obj.rect.width;
            yy := fy + p.obj.rect.y + (p.obj.rect.height - IndicatorTexture.width) div 2;
          end
          else if (p.obj.x + p.obj.rect.x + p.obj.rect.width) > (cx + cw) then
          begin
            a := 270;
            xx := fx + p.obj.rect.x - IndicatorTexture.height;
            yy := fy + p.obj.rect.y - (p.obj.rect.height - IndicatorTexture.width) div 2;
          end
          else if (p.obj.y - IndicatorTexture.height) < cy then
          begin
            a := 180;
            xx := fx + p.obj.rect.x + (p.obj.rect.width - IndicatorTexture.width) div 2;
            yy := fy + p.obj.rect.y + p.obj.rect.height;
          end
          else
          begin
            a := 0;
            xx := fx + p.obj.rect.x + (p.obj.rect.width - IndicatorTexture.width) div 2;
            yy := fy - IndicatorTexture.height;
          end;
          xx := MIN(MAX(xx, cx), cx + cw - IndicatorTexture.width);
          yy := MIN(MAX(yy, cy), cy + ch - IndicatorTexture.height);
          r_Draw_TextureRepeatRotate(IndicatorTexture, xx, yy, IndicatorTexture.width, IndicatorTexture.height, false, color.r, color.g, color.b, 255, false, ax, ay, a);
        end;
        1:
        begin
          xx := fx + p.obj.rect.x + p.obj.rect.width div 2;
          yy := fy;
          r_Common_DrawText(p.Name, xx, yy, color.r, color.g, color.b, 255, stdfont, TBasePoint.BP_DOWN);
        end;
      end;
    end;
  end;

  procedure r_Map_DrawPlayerIndicators (player: TPlayer; cx, cy, cw, ch: Integer);
    var i: Integer; p: TPlayer;
  begin
    case gPlayerIndicator of
      1:
      if player <> nil then
      begin
        r_Map_DrawIndicator(player, _RGB(255, 255, 255), cx, cy, cw, ch);
      end;
      2:
      if gPlayers <> nil then
      begin
        for i := 0 to HIGH(gPlayers) do
        begin
          p := gPlayers[i];
          if p <> nil then
          begin
            if (player <> nil) and (p = player) then
            begin
              r_Map_DrawIndicator(p, _RGB(255, 255, 255), cx, cy, cw, ch);
            end
            else if (player = nil) or ((p.Team = player.Team) and (p.Team <> TEAM_NONE)) then
            begin
              case gPlayerIndicatorStyle of
                0: r_Map_DrawIndicator(p, p.GetColor(), cx, cy, cw, ch);
                1: r_Map_DrawIndicator(p, _RGB(192, 192, 192), cx, cy, cw, ch);
              end;
            end;
          end;
        end;
      end;
    end;
  end;

  procedure r_Map_Draw (x, y, w, h, camx, camy: Integer; player: TPlayer);
    var iter: TPanelGrid.Iter; p: PPanel; cx, cy, cw, ch, xx, yy, ww, hh, ml, mt, mr, mb, mcx, mcy: Integer; sx, sy, sw, sh: LongInt; l, t, r, b: Integer;
  begin
    r_Draw_GetRect(l, t, r, b);
    glTranslatef(x, y, 0);

    (* camera rect *)
    cx := (camx - w) + w div 2;
    cy := (camy - h) + h div 2;
    cw := w;
    ch := h;

    (* camera bounds *)
    if g_dbg_ignore_bounds = false then
    begin
      if w > gMapInfo.Width then
        cx := gMapInfo.Width div 2 - w div 2
      else if cx + cw > gMapInfo.Width then
        cx := gMapInfo.Width - cw
      else if cx < 0 then
        cx := 0;

      if h > gMapInfo.Height then
        cy := gMapInfo.Height div 2 - h div 2
      else if cy + ch > gMapInfo.Height then
        cy := gMapInfo.Height - ch
      else if cy < 0 then
        cy := 0;
    end;

    (* map bounds *)
    xx := cx;
    yy := cy;
    ww := cw;
    hh := ch;
    if xx + ww > gMapInfo.Width then
      xx := gMapInfo.Width - ww;
    if yy + hh > gMapInfo.Height then
      yy := gMapInfo.Height - hh;
    if xx < 0 then
      xx := 0;
    if yy < 0 then
      yy := 0;

    (* view bounds *)
    ml := x; mt := y; mr := x + w; mb := y + h;
    if FillOutsizeArea and (DebugCameraScale = 1.0) then
    begin
      ml := MAX(cx + ml, 0) - cx;
      mt := MAX(cy + mt, 0) - cy;
      mr := MIN(cx + mr, gMapInfo.Width - 1) - cx;
      mb := MIN(cy + mb, gMapInfo.Height - 1) - cy;
    end;
    r_Draw_SetRect(ml, mt, mr, mb);

    plist.Clear;
    iter := mapGrid.ForEachInAABB(xx, yy, ww, hh, GridDrawableMask);
    for p in iter do
      if ((p^.tag and GridTagDoor) <> 0) = p^.door then
        plist.Insert(p^);
    iter.Release;

    glPushMatrix;
    if DebugCameraScale <> 1.0 then
    begin
      glTranslatef(cw div 2, ch div 2, 0);
      glScalef(DebugCameraScale, DebugCameraScale, 1);
      glTranslatef(-w div 2, -h div 2, 0);
    end;

    if SkyTexture <> nil then
    begin
      r_Map_CalcSkyParallax(cx, cy, w, h, SkyTexture.width, SkyTexture.height, gMapInfo.Width, gMapInfo.Height, sx, sy, sw, sh);
      r_Draw_Texture(SkyTexture, sx, sy, sw, sh, false, 255, 255, 255, 255, false);
    end;

    glTranslatef(-cx, -cy, 0);
    r_Map_DrawPanelType(PANEL_BACK);
    r_Map_DrawPanelType(PANEL_STEP);
    r_Map_DrawItems(xx, yy, ww, hh, false);
    r_Map_DrawShots(xx, yy, ww, hh);
    {$IFDEF ENABLE_SHELLS}
      r_Map_DrawShells(xx, yy, ww, hh);
    {$ENDIF}
    r_Map_DrawPlayers(xx, yy, ww, hh, player);
    {$IFDEF ENABLE_GIBS}
      r_Map_DrawGibs(xx, yy, ww, hh);
    {$ENDIF}
    {$IFDEF ENABLE_CORPSES}
      r_Map_DrawCorpses(xx, yy, ww, hh);
    {$ENDIF}
    r_Map_DrawPanelType(PANEL_WALL);
    r_Map_DrawMonsters(xx, yy, ww, hh);
    r_Map_DrawItems(xx, yy, ww, hh, true);
    r_Map_DrawPanelType(PANEL_CLOSEDOOR);
    {$IFDEF ENABLE_GFX}
      r_Map_DrawParticles(xx, yy, ww, hh);
      r_Map_DrawGFX(xx, yy, ww, hh);
    {$ENDIF}
    r_Map_DrawFlags(xx, yy, ww, hh);
    r_Map_DrawPanelType(PANEL_ACID1);
    r_Map_DrawPanelType(PANEL_ACID2);
    r_Map_DrawPanelType(PANEL_WATER);
    r_Map_DrawPanelType(PANEL_FORE);
    // TODO draw monsters health bar
    // TODO draw players health bar
    if gGameSettings.GameMode <> GM_SINGLE then
      r_Map_DrawPlayerIndicators(player, cx, cy, cw, ch);
    if DebugCameraScale <> 1.0 then
    begin
      r_Draw_Rect (cx, cy, cx + cw, cy + ch, 0, 255, 0, 255);
      r_Draw_Rect (xx, yy, xx + ww, yy + hh, 255, 0, 0, 255);
    end;
    glPopMatrix;

    r_Map_DrawScreenEffects(x, y, w, h, player);

    // TODO draw g_debug_player

    glTranslatef(-x, -y, 0);
    r_Draw_SetRect(l, t, r, b);
  end;

  procedure r_Map_Update;
    var i, count, tick: LongInt;
  begin
    tick := gTime div GAME_TICK;
    for i := 0 to ITEM_LAST do
      g_Anim_GetFrameByTime(ItemAnim[i].anim, tick, count, Items[i].frame);
    r_Map_UpdateGFX(tick);
    g_Anim_GetFrameByTime(FlagAnim, tick, count, FlagFrame);
  end;

initialization
  conRegVar('r_debug_camera_scale', @DebugCameraScale, 0.0001, 1000.0, '', '');
  conRegVar('r_gl_fill_outside', @FillOutsizeArea, '', '');
  DebugCameraScale := 1.0;
  FillOutsizeArea := true;
end.
