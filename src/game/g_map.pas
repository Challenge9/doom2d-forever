(* Copyright (C)  DooM 2D:Forever Developers
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *)
{$MODE DELPHI}
unit g_map;

interface

uses
  e_graphics, g_basic, MAPSTRUCT, g_textures, Classes,
  g_phys, wadreader, BinEditor, g_panel, md5;

type
  TMapInfo = record
    Map:           String;
    Name:          String;
    Description:   String;
    Author:        String;
    MusicName:     String;
    SkyName:       String;
    Height:        Word;
    Width:         Word;
  end;

  PRespawnPoint = ^TRespawnPoint;
  TRespawnPoint = record
    X, Y:      Integer;
    Direction: TDirection;
    PointType: Byte;
  end;

  PFlagPoint = ^TFlagPoint;
  TFlagPoint = TRespawnPoint;

  PFlag = ^TFlag;
  TFlag = record
    Obj:         TObj;
    RespawnType: Byte;
    State:       Byte;
    Count:       Integer;
    CaptureTime: LongWord;
    Animation:   TAnimation;
    Direction:   TDirection;
  end;

function  g_Map_Load(Res: String): Boolean;
function  g_Map_GetMapInfo(Res: String): TMapInfo;
function  g_Map_GetMapsList(WADName: String): SArray;
function  g_Map_Exist(Res: String): Boolean;
procedure g_Map_Free();
procedure g_Map_Update();

// build "potentially visible panels" set, so we can avoid looping over all level panels again and again
procedure g_Map_BuildPVP (minx, miny, maxx, maxy: Integer);
procedure g_Map_ResetPVP ();
// do not call this without calling `g_Map_BuildPVP()` or `g_Map_ResetPVP()` first!
procedure g_Map_DrawPanels(PanelType: Word);

procedure g_Map_DrawBack(dx, dy: Integer);
function  g_Map_CollidePanel(X, Y: Integer; Width, Height: Word;
                             PanelType: Word; b1x3: Boolean): Boolean;
function  g_Map_CollideLiquid_Texture(X, Y: Integer; Width, Height: Word): DWORD;
procedure g_Map_EnableWall(ID: DWORD);
procedure g_Map_DisableWall(ID: DWORD);
procedure g_Map_SwitchTexture(PanelType: Word; ID: DWORD; AnimLoop: Byte = 0);
procedure g_Map_SetLift(ID: DWORD; t: Integer);
procedure g_Map_ReAdd_DieTriggers();
function  g_Map_IsSpecialTexture(Texture: String): Boolean;

function  g_Map_GetPoint(PointType: Byte; var RespawnPoint: TRespawnPoint): Boolean;
function  g_Map_GetPointCount(PointType: Byte): Word;

function  g_Map_HaveFlagPoints(): Boolean;

procedure g_Map_ResetFlag(Flag: Byte);
procedure g_Map_DrawFlags();

function g_Map_PanelForPID(PanelID: Integer; var PanelArrayID: Integer): PPanel;

procedure g_Map_SaveState(Var Mem: TBinMemoryWriter);
procedure g_Map_LoadState(Var Mem: TBinMemoryReader);

// build "possibly lit panels" index, so we can avoid looping over all level panels again and again
function g_Map_BuildPLP (ltminx, ltminy, ltmaxx, ltmaxy: Integer): Boolean; // returns `false` if no patels lit
procedure g_Map_DrawPanelShadowVolumes(lightX: Integer; lightY: Integer; radius: Integer);

const
  RESPAWNPOINT_PLAYER1 = 1;
  RESPAWNPOINT_PLAYER2 = 2;
  RESPAWNPOINT_DM      = 3;
  RESPAWNPOINT_RED     = 4;
  RESPAWNPOINT_BLUE    = 5;

  FLAG_NONE = 0;
  FLAG_RED  = 1;
  FLAG_BLUE = 2;
  FLAG_DOM  = 3;

  FLAG_STATE_NONE     = 0;
  FLAG_STATE_NORMAL   = 1;
  FLAG_STATE_DROPPED  = 2;
  FLAG_STATE_CAPTURED = 3;
  FLAG_STATE_SCORED   = 4; // ��� ������� ����� �����.
  FLAG_STATE_RETURNED = 5; // ��� ������� ����� �����.

  FLAG_TIME = 720; // 20 seconds

  SKY_STRETCH: Single = 1.5;

var
  gWalls: TPanelArray;
  gRenderBackgrounds: TPanelArray;
  gRenderForegrounds: TPanelArray;
  gWater, gAcid1, gAcid2: TPanelArray;
  gSteps: TPanelArray;
  gLifts: TPanelArray;
  gBlockMon: TPanelArray;
  gFlags: array [FLAG_RED..FLAG_BLUE] of TFlag;
  //gDOMFlags: array of TFlag;
  gMapInfo: TMapInfo;
  gBackSize: TPoint;
  gDoorMap: array of array of DWORD;
  gLiftMap: array of array of DWORD;
  gWADHash: TMD5Digest;
  BackID:  DWORD = DWORD(-1);
  gExternalResources: TStringList;

implementation

uses
  g_main, e_log, SysUtils, g_items, g_gfx, g_console,
  GL, GLExt, g_weapons, g_game, g_sound, e_sound, CONFIG,
  g_options, MAPREADER, g_triggers, g_player, MAPDEF,
  Math, g_monsters, g_saveload, g_language, g_netmsg,
  utils, sfs,
  ImagingTypes, Imaging, ImagingUtility,
  ImagingGif, ImagingNetworkGraphics;

const
  FLAGRECT: TRectWH = (X:15; Y:12; Width:33; Height:52);
  MUSIC_SIGNATURE = $4953554D; // 'MUSI'
  FLAG_SIGNATURE = $47414C46; // 'FLAG'

type
  TPanelID = record
    PWhere: ^TPanelArray;
    PArrID: Integer;
  end;

var
  PanelById:     array of TPanelID;
  Textures:      TLevelTextureArray;
  RespawnPoints: Array of TRespawnPoint;
  FlagPoints:    Array [FLAG_RED..FLAG_BLUE] of PFlagPoint;
  //DOMFlagPoints: Array of TFlagPoint;


function g_Map_IsSpecialTexture(Texture: String): Boolean;
begin
  Result := (Texture = TEXTURE_NAME_WATER) or
            (Texture = TEXTURE_NAME_ACID1) or
            (Texture = TEXTURE_NAME_ACID2);
end;

procedure CreateDoorMap();
var
  PanelArray: Array of record
                         X, Y: Integer;
                         Width, Height: Word;
                         Active: Boolean;
                         PanelID: DWORD;
                       end;
  a, b, c, m, i, len: Integer;
  ok: Boolean;
begin
  if gWalls = nil then
    Exit;

  i := 0;
  len := 128;
  SetLength(PanelArray, len);

  for a := 0 to High(gWalls) do
    if gWalls[a].Door then
    begin
      PanelArray[i].X := gWalls[a].X;
      PanelArray[i].Y := gWalls[a].Y;
      PanelArray[i].Width := gWalls[a].Width;
      PanelArray[i].Height := gWalls[a].Height;
      PanelArray[i].Active := True;
      PanelArray[i].PanelID := a;

      i := i + 1;
      if i = len then
      begin
        len := len + 128;
        SetLength(PanelArray, len);
      end;
    end;

// ��� ������:
  if i = 0 then
  begin
    PanelArray := nil;
    Exit;
  end;

  SetLength(gDoorMap, 0);

  g_Game_SetLoadingText(_lc[I_LOAD_DOOR_MAP], i-1, False);

  for a := 0 to i-1 do
    if PanelArray[a].Active then
    begin
      PanelArray[a].Active := False;
      m := Length(gDoorMap);
      SetLength(gDoorMap, m+1);
      SetLength(gDoorMap[m], 1);
      gDoorMap[m, 0] := PanelArray[a].PanelID;
      ok := True;

      while ok do
      begin
        ok := False;

        for b := 0 to i-1 do
          if PanelArray[b].Active then
            for c := 0 to High(gDoorMap[m]) do
              if {((gRenderWalls[PanelArray[b].RenderPanelID].TextureID = gRenderWalls[gDoorMap[m, c]].TextureID) or
                    gRenderWalls[PanelArray[b].RenderPanelID].Hide or gRenderWalls[gDoorMap[m, c]].Hide) and}
                g_CollideAround(PanelArray[b].X, PanelArray[b].Y,
                                PanelArray[b].Width, PanelArray[b].Height,
                                gWalls[gDoorMap[m, c]].X,
                                gWalls[gDoorMap[m, c]].Y,
                                gWalls[gDoorMap[m, c]].Width,
                                gWalls[gDoorMap[m, c]].Height) then
              begin
                PanelArray[b].Active := False;
                SetLength(gDoorMap[m],
                          Length(gDoorMap[m])+1);
                gDoorMap[m, High(gDoorMap[m])] := PanelArray[b].PanelID;
                ok := True;
                Break;
              end;
      end;

      g_Game_StepLoading();
    end;

  PanelArray := nil;
end;

procedure CreateLiftMap();
var
  PanelArray: Array of record
                         X, Y: Integer;
                         Width, Height: Word;
                         Active: Boolean;
                       end;
  a, b, c, len, i, j: Integer;
  ok: Boolean;
begin
  if gLifts = nil then
    Exit;

  len := Length(gLifts);
  SetLength(PanelArray, len);

  for a := 0 to len-1 do
  begin
    PanelArray[a].X := gLifts[a].X;
    PanelArray[a].Y := gLifts[a].Y;
    PanelArray[a].Width := gLifts[a].Width;
    PanelArray[a].Height := gLifts[a].Height;
    PanelArray[a].Active := True;
  end;

  SetLength(gLiftMap, len);
  i := 0;

  g_Game_SetLoadingText(_lc[I_LOAD_LIFT_MAP], len-1, False);

  for a := 0 to len-1 do
    if PanelArray[a].Active then
    begin
      PanelArray[a].Active := False;
      SetLength(gLiftMap[i], 32);
      j := 0;
      gLiftMap[i, j] := a;
      ok := True;

      while ok do
      begin
        ok := False;
        for b := 0 to len-1 do
          if PanelArray[b].Active then
            for c := 0 to j do
              if g_CollideAround(PanelArray[b].X,
                                 PanelArray[b].Y,
                                 PanelArray[b].Width,
                                 PanelArray[b].Height,
                                 PanelArray[gLiftMap[i, c]].X,
                                 PanelArray[gLiftMap[i, c]].Y,
                                 PanelArray[gLiftMap[i, c]].Width,
                                 PanelArray[gLiftMap[i, c]].Height) then
              begin
                PanelArray[b].Active := False;
                j := j+1;
                if j > High(gLiftMap[i]) then
                  SetLength(gLiftMap[i],
                            Length(gLiftMap[i])+32);

                gLiftMap[i, j] := b;
                ok := True;

                Break;
              end;
      end;

      SetLength(gLiftMap[i], j+1);
      i := i+1;

      g_Game_StepLoading();
    end;

  SetLength(gLiftMap, i);

  PanelArray := nil;
end;

function CreatePanel(PanelRec: TPanelRec_1; AddTextures: TAddTextureArray;
                     CurTex: Integer; sav: Boolean): Integer;
var
  len: Integer;
  panels: ^TPanelArray;
begin
  Result := -1;

  case PanelRec.PanelType of
    PANEL_WALL, PANEL_OPENDOOR, PANEL_CLOSEDOOR:
      panels := @gWalls;
    PANEL_BACK:
      panels := @gRenderBackgrounds;
    PANEL_FORE:
      panels := @gRenderForegrounds;
    PANEL_WATER:
      panels := @gWater;
    PANEL_ACID1:
      panels := @gAcid1;
    PANEL_ACID2:
      panels := @gAcid2;
    PANEL_STEP:
      panels := @gSteps;
    PANEL_LIFTUP, PANEL_LIFTDOWN, PANEL_LIFTLEFT, PANEL_LIFTRIGHT:
      panels := @gLifts;
    PANEL_BLOCKMON:
      panels := @gBlockMon;
    else
      Exit;
  end;

  len := Length(panels^);
  SetLength(panels^, len + 1);

  panels^[len] := TPanel.Create(PanelRec, AddTextures,
                                CurTex, Textures);
  if sav then
    panels^[len].SaveIt := True;

  Result := len;

  len := Length(PanelByID);
  SetLength(PanelByID, len + 1);
  PanelByID[len].PWhere := panels;
  PanelByID[len].PArrID := Result;
end;

function CreateNullTexture(RecName: String): Integer;
begin
  SetLength(Textures, Length(Textures)+1);
  result := High(Textures);

  with Textures[High(Textures)] do
  begin
    TextureName := RecName;
    Width := 1;
    Height := 1;
    Anim := False;
    TextureID := TEXTURE_NONE;
  end;
end;

function CreateTexture(RecName: String; Map: string; log: Boolean): Integer;
var
  WAD: TWADFile;
  TextureData: Pointer;
  WADName, txname: String;
  a, ResLength: Integer;
begin
  Result := -1;

  if Textures <> nil then
    for a := 0 to High(Textures) do
      if Textures[a].TextureName = RecName then
      begin // �������� � ����� ������ ��� ����
        Result := a;
        Exit;
      end;

// �������� �� ������������ ������� (����, ����, �������):
  if (RecName = TEXTURE_NAME_WATER) or
     (RecName = TEXTURE_NAME_ACID1) or
     (RecName = TEXTURE_NAME_ACID2) then
  begin
    SetLength(Textures, Length(Textures)+1);

    with Textures[High(Textures)] do
    begin
      TextureName := RecName;

      if TextureName = TEXTURE_NAME_WATER then
        TextureID := TEXTURE_SPECIAL_WATER
      else
        if TextureName = TEXTURE_NAME_ACID1 then
          TextureID := TEXTURE_SPECIAL_ACID1
        else
          if TextureName = TEXTURE_NAME_ACID2 then
            TextureID := TEXTURE_SPECIAL_ACID2;

      Anim := False;
    end;

    result := High(Textures);
    Exit;
  end;

// ��������� ������ �������� � ������ �� WAD'�:
  WADName := g_ExtractWadName(RecName);

  WAD := TWADFile.Create();

  if WADName <> '' then
    WADName := GameDir+'/wads/'+WADName
  else
    WADName := Map;

  WAD.ReadFile(WADName);

  txname := RecName;
  {
  if (WADName = Map) and WAD.GetResource(g_ExtractFilePathName(RecName), TextureData, ResLength) then
  begin
    FreeMem(TextureData);
    RecName := 'COMMON\ALIEN';
  end;
  }

  if WAD.GetResource(g_ExtractFilePathName(RecName), TextureData, ResLength) then
    begin
      SetLength(Textures, Length(Textures)+1);
      if not e_CreateTextureMem(TextureData, ResLength, Textures[High(Textures)].TextureID) then
        Exit;
      e_GetTextureSize(Textures[High(Textures)].TextureID,
                       @Textures[High(Textures)].Width,
                       @Textures[High(Textures)].Height);
      FreeMem(TextureData);
      Textures[High(Textures)].TextureName := {RecName}txname;
      Textures[High(Textures)].Anim := False;

      result := High(Textures);
    end
  else // ��� ������ ������� � WAD'�
  begin
    //e_WriteLog(Format('SHIT! Error loading texture %s : %s : %s', [RecName, txname, g_ExtractFilePathName(RecName)]), MSG_WARNING);
    if log then
      begin
        e_WriteLog(Format('Error loading texture %s', [RecName]), MSG_WARNING);
        //e_WriteLog(Format('WAD Reader error: %s', [WAD.GetLastErrorStr]), MSG_WARNING);
      end;
  end;

  WAD.Free();
end;

function CreateAnimTexture(RecName: String; Map: string; log: Boolean): Integer;
var
  WAD: TWADFile;
  TextureWAD: PChar = nil;
  TextData: Pointer = nil;
  TextureData: Pointer = nil;
  cfg: TConfig = nil;
  WADName: String;
  ResLength: Integer;
  TextureResource: String;
  _width, _height, _framecount, _speed: Integer;
  _backanimation: Boolean;
  //imgfmt: string;
  ia: TDynImageDataArray = nil;
  f, c, frdelay, frloop: Integer;
begin
  result := -1;

  //e_WriteLog(Format('*** Loading animated texture "%s"', [RecName]), MSG_NOTIFY);

  // ������ WAD-������ ����.�������� �� WAD'� � ������:
  WADName := g_ExtractWadName(RecName);

  WAD := TWADFile.Create();
  try
    if WADName <> '' then
      WADName := GameDir+'/wads/'+WADName
    else
      WADName := Map;

    WAD.ReadFile(WADName);

    if not WAD.GetResource(g_ExtractFilePathName(RecName), TextureWAD, ResLength) then
    begin
      if log then
      begin
        e_WriteLog(Format('Error loading animation texture %s', [RecName]), MSG_WARNING);
        //e_WriteLog(Format('WAD Reader error: %s', [WAD.GetLastErrorStr]), MSG_WARNING);
      end;
      exit;
    end;

    {TEST
    if WADName = Map then
    begin
      //FreeMem(TextureWAD);
      if not WAD.GetResource('COMMON/animation', TextureWAD, ResLength) then Halt(1);
    end;
    }

    WAD.FreeWAD();

    if ResLength < 6 then
    begin
      e_WriteLog(Format('Animated texture file "%s" too short', [RecName]), MSG_WARNING);
      exit;
    end;

    // ��� �����? ��� ������?
    if (TextureWAD[0] = 'D') and (TextureWAD[1] = 'F') and
       (TextureWAD[2] = 'W') and (TextureWAD[3] = 'A') and (TextureWAD[4] = 'D') then
    begin
      // ���, ��� ��������!
      if not WAD.ReadMemory(TextureWAD, ResLength) then
      begin
        e_WriteLog(Format('Animated texture WAD file "%s" is invalid', [RecName]), MSG_WARNING);
        exit;
      end;

      // ������ INI-������ ����. �������� � ���������� ��� ���������:
      if not WAD.GetResource('TEXT/ANIM', TextData, ResLength) then
      begin
        e_WriteLog(Format('Animated texture file "%s" has invalid INI', [RecName]), MSG_WARNING);
        exit;
      end;

      cfg := TConfig.CreateMem(TextData, ResLength);

      TextureResource := cfg.ReadStr('', 'resource', '');
      if TextureResource = '' then
      begin
        e_WriteLog(Format('Animated texture WAD file "%s" has no "resource"', [RecName]), MSG_WARNING);
        exit;
      end;

      _width := cfg.ReadInt('', 'framewidth', 0);
      _height := cfg.ReadInt('', 'frameheight', 0);
      _framecount := cfg.ReadInt('', 'framecount', 0);
      _speed := cfg.ReadInt('', 'waitcount', 0);
      _backanimation := cfg.ReadBool('', 'backanimation', False);

      cfg.Free();
      cfg := nil;

      // ������ ������ ������� (������) ����. �������� � ������:
      if not WAD.GetResource('TEXTURES/'+TextureResource, TextureData, ResLength) then
      begin
        e_WriteLog(Format('Animated texture WAD file "%s" has no texture "%s"', [RecName, 'TEXTURES/'+TextureResource]), MSG_WARNING);
        exit;
      end;

      WAD.Free();
      WAD := nil;

      SetLength(Textures, Length(Textures)+1);
      with Textures[High(Textures)] do
      begin
        // ������� ����� ����. �������� �� ������:
        if g_Frames_CreateMemory(@FramesID, '', TextureData, ResLength, _width, _height, _framecount, _backanimation) then
        begin
          TextureName := RecName;
          Width := _width;
          Height := _height;
          Anim := True;
          FramesCount := _framecount;
          Speed := _speed;
          result := High(Textures);
        end
        else
        begin
          if log then e_WriteLog(Format('Error loading animation texture %s', [RecName]), MSG_WARNING);
        end;
      end;
    end
    else
    begin
      // try animated image
      {
      imgfmt := DetermineMemoryFormat(TextureWAD, ResLength);
      if length(imgfmt) = 0 then
      begin
        e_WriteLog(Format('Animated texture file "%s" has unknown format', [RecName]), MSG_WARNING);
        exit;
      end;
      }
      GlobalMetadata.ClearMetaItems();
      GlobalMetadata.ClearMetaItemsForSaving();
      if not LoadMultiImageFromMemory(TextureWAD, ResLength, ia) then
      begin
        e_WriteLog(Format('Animated texture file "%s" cannot be loaded', [RecName]), MSG_WARNING);
        exit;
      end;
      if length(ia) = 0 then
      begin
        e_WriteLog(Format('Animated texture file "%s" has no frames', [RecName]), MSG_WARNING);
        exit;
      end;

      WAD.Free();
      WAD := nil;

      _width := ia[0].width;
      _height := ia[0].height;
      _framecount := length(ia);
      _speed := 1;
      _backanimation := false;
      frdelay := -1;
      frloop := -666;
      if GlobalMetadata.HasMetaItem(SMetaFrameDelay) then
      begin
        //writeln(' frame delay: ', GlobalMetadata.MetaItems[SMetaFrameDelay]);
        try
          f := GlobalMetadata.MetaItems[SMetaFrameDelay];
          frdelay := f;
          if f < 0 then f := 0;
          // rounding ;-)
          c := f mod 28;
          if c < 13 then c := 0 else c := 1;
          f := (f div 28)+c;
          if f < 1 then f := 1 else if f > 255 then f := 255;
          _speed := f;
        except
        end;
      end;
      if GlobalMetadata.HasMetaItem(SMetaAnimationLoops) then
      begin
        //writeln(' frame loop : ', GlobalMetadata.MetaItems[SMetaAnimationLoops]);
        try
          f := GlobalMetadata.MetaItems[SMetaAnimationLoops];
          frloop := f;
          if f <> 0 then _backanimation := true; // non-infinite looping == forth-and-back
        except
        end;
      end;
      //writeln(' creating animated texture with ', length(ia), ' frames (delay:', _speed, '; backloop:', _backanimation, ') from "', RecName, '"...');
      //for f := 0 to high(ia) do writeln('  frame #', f, ': ', ia[f].width, 'x', ia[f].height);
      f := ord(_backanimation);
      e_WriteLog(Format('Animated texture file "%s": %d frames (delay:%d; back:%d; frdelay:%d; frloop:%d), %dx%d', [RecName, length(ia), _speed, f, frdelay, frloop, _width, _height]), MSG_NOTIFY);

      SetLength(Textures, Length(Textures)+1);
      // c������ ����� ����. �������� �� ��������
      if g_CreateFramesImg(ia, @Textures[High(Textures)].FramesID, '', _backanimation) then
      begin
        Textures[High(Textures)].TextureName := RecName;
        Textures[High(Textures)].Width := _width;
        Textures[High(Textures)].Height := _height;
        Textures[High(Textures)].Anim := True;
        Textures[High(Textures)].FramesCount := length(ia);
        Textures[High(Textures)].Speed := _speed;
        result := High(Textures);
        //writeln(' CREATED!');
      end
      else
      begin
        if log then e_WriteLog(Format('Error loading animation texture "%s" images', [RecName]), MSG_WARNING);
      end;
    end;
  finally
    for f := 0 to High(ia) do FreeImage(ia[f]);
    WAD.Free();
    cfg.Free();
    if TextureWAD <> nil then FreeMem(TextureWAD);
    if TextData <> nil then FreeMem(TextData);
    if TextureData <> nil then FreeMem(TextureData);
  end;
end;

procedure CreateItem(Item: TItemRec_1);
begin
  if g_Game_IsClient then Exit;

  if (not (gGameSettings.GameMode in [GM_DM, GM_TDM, GM_CTF])) and
     ByteBool(Item.Options and ITEM_OPTION_ONLYDM) then
    Exit;

  g_Items_Create(Item.X, Item.Y, Item.ItemType, ByteBool(Item.Options and ITEM_OPTION_FALL),
                 gGameSettings.GameMode in [GM_DM, GM_TDM, GM_CTF, GM_COOP]);
end;

procedure CreateArea(Area: TAreaRec_1);
var
  a: Integer;
  id: DWORD;
begin
  case Area.AreaType of
    AREA_DMPOINT, AREA_PLAYERPOINT1, AREA_PLAYERPOINT2,
    AREA_REDTEAMPOINT, AREA_BLUETEAMPOINT:
    begin
      SetLength(RespawnPoints, Length(RespawnPoints)+1);
      with RespawnPoints[High(RespawnPoints)] do
      begin
        X := Area.X;
        Y := Area.Y;
        Direction := TDirection(Area.Direction);

        case Area.AreaType of
          AREA_DMPOINT: PointType := RESPAWNPOINT_DM;
          AREA_PLAYERPOINT1: PointType := RESPAWNPOINT_PLAYER1;
          AREA_PLAYERPOINT2: PointType := RESPAWNPOINT_PLAYER2;
          AREA_REDTEAMPOINT: PointType := RESPAWNPOINT_RED;
          AREA_BLUETEAMPOINT: PointType := RESPAWNPOINT_BLUE;
        end;
      end;
    end;

    AREA_REDFLAG, AREA_BLUEFLAG:
    begin
      if Area.AreaType = AREA_REDFLAG then a := FLAG_RED else a := FLAG_BLUE;

      if FlagPoints[a] <> nil then Exit;

      New(FlagPoints[a]);

      with FlagPoints[a]^ do
      begin
        X := Area.X-FLAGRECT.X;
        Y := Area.Y-FLAGRECT.Y;
        Direction := TDirection(Area.Direction);
      end;

      with gFlags[a] do
      begin
        case a of
          FLAG_RED: g_Frames_Get(id, 'FRAMES_FLAG_RED');
          FLAG_BLUE: g_Frames_Get(id, 'FRAMES_FLAG_BLUE');
        end;

        Animation := TAnimation.Create(id, True, 8);
        Obj.Rect := FLAGRECT;

        g_Map_ResetFlag(a);
      end;
    end;

    AREA_DOMFLAG:
    begin
      {SetLength(DOMFlagPoints, Length(DOMFlagPoints)+1);
      with DOMFlagPoints[High(DOMFlagPoints)] do
      begin
        X := Area.X;
        Y := Area.Y;
        Direction := TDirection(Area.Direction);
      end;

      g_Map_CreateFlag(DOMFlagPoints[High(DOMFlagPoints)], FLAG_DOM, FLAG_STATE_NORMAL);}
    end;
  end;
end;

procedure CreateTrigger(Trigger: TTriggerRec_1; fTexturePanel1Type, fTexturePanel2Type: Word);
var
  _trigger: TTrigger;
begin
  if g_Game_IsClient and not (Trigger.TriggerType in [TRIGGER_SOUND, TRIGGER_MUSIC]) then Exit;

  with _trigger do
  begin
    X := Trigger.X;
    Y := Trigger.Y;
    Width := Trigger.Width;
    Height := Trigger.Height;
    Enabled := ByteBool(Trigger.Enabled);
    TexturePanel := Trigger.TexturePanel;
    TexturePanelType := fTexturePanel1Type;
    ShotPanelType := fTexturePanel2Type;
    TriggerType := Trigger.TriggerType;
    ActivateType := Trigger.ActivateType;
    Keys := Trigger.Keys;
    Data.Default := Trigger.DATA;
  end;

  g_Triggers_Create(_trigger);
end;

procedure CreateMonster(monster: TMonsterRec_1);
var
  a, i: Integer;
begin
  if g_Game_IsClient then Exit;

  if (gGameSettings.GameType = GT_SINGLE)
  or LongBool(gGameSettings.Options and GAME_OPTION_MONSTERS) then
  begin
    i := g_Monsters_Create(monster.MonsterType, monster.X, monster.Y,
                           TDirection(monster.Direction));

    if gTriggers <> nil then
      for a := 0 to High(gTriggers) do
        if gTriggers[a].TriggerType in [TRIGGER_PRESS,
             TRIGGER_ON, TRIGGER_OFF, TRIGGER_ONOFF] then
          if (gTriggers[a].Data.MonsterID-1) = gMonsters[i].StartID then
            gMonsters[i].AddTrigger(a);

    if monster.MonsterType <> MONSTER_BARREL then
      Inc(gTotalMonsters);
  end;
end;

procedure g_Map_ReAdd_DieTriggers();
var
  i, a: Integer;
begin
  if g_Game_IsClient then Exit;

  for i := 0 to High(gMonsters) do
    if gMonsters[i] <> nil then
      begin
        gMonsters[i].ClearTriggers();

        for a := 0 to High(gTriggers) do
          if gTriggers[a].TriggerType in [TRIGGER_PRESS,
               TRIGGER_ON, TRIGGER_OFF, TRIGGER_ONOFF] then
            if (gTriggers[a].Data.MonsterID-1) = gMonsters[i].StartID then
              gMonsters[i].AddTrigger(a);
      end;
end;

function extractWadName(resourceName: string): string;
var
  posN: Integer;
begin
  posN := Pos(':', resourceName);
  if posN > 0 then
    Result:= Copy(resourceName, 0, posN-1)
  else
    Result := '';
end;

procedure addResToExternalResList(res: string);
begin
  res := extractWadName(res);
  if (res <> '') and (gExternalResources.IndexOf(res) = -1) then
    gExternalResources.Add(res);
end;

procedure generateExternalResourcesList(mapReader: TMapReader_1);
var
  textures: TTexturesRec1Array;
  mapHeader: TMapHeaderRec_1;
  i: integer;
  resFile: String = '';
begin
  if gExternalResources = nil then
    gExternalResources := TStringList.Create;

  gExternalResources.Clear;
  textures := mapReader.GetTextures();
  for i := 0 to High(textures) do
  begin
    addResToExternalResList(resFile);
  end;

  textures := nil;

  mapHeader := mapReader.GetMapHeader;

  addResToExternalResList(mapHeader.MusicName);
  addResToExternalResList(mapHeader.SkyName);
end;

function g_Map_Load(Res: String): Boolean;
const
  DefaultMusRes = 'Standart.wad:STDMUS\MUS1';
  DefaultSkyRes = 'Standart.wad:STDSKY\SKY0';
var
  WAD: TWADFile;
  MapReader: TMapReader_1;
  Header: TMapHeaderRec_1;
  _textures: TTexturesRec1Array;
  _texnummap: array of Integer; // `_textures` -> `Textures`
  panels: TPanelsRec1Array;
  items: TItemsRec1Array;
  monsters: TMonsterRec1Array;
  areas: TAreasRec1Array;
  triggers: TTriggersRec1Array;
  a, b, c, k: Integer;
  PanelID: DWORD;
  AddTextures: TAddTextureArray;
  texture: TTextureRec_1;
  TriggersTable: Array of record
                           TexturePanel: Integer;
                           LiftPanel: Integer;
                           DoorPanel: Integer;
                           ShotPanel: Integer;
                          end;
  FileName, mapResName, s, TexName: String;
  Data: Pointer;
  Len: Integer;
  ok, isAnim, trigRef: Boolean;
  CurTex, ntn: Integer;
begin
  Result := False;
  gMapInfo.Map := Res;
  TriggersTable := nil;
  FillChar(texture, SizeOf(texture), 0);

  sfsGCDisable(); // temporary disable removing of temporary volumes
  try
  // �������� WAD:
    FileName := g_ExtractWadName(Res);
    e_WriteLog('Loading map WAD: '+FileName, MSG_NOTIFY);
    g_Game_SetLoadingText(_lc[I_LOAD_WAD_FILE], 0, False);

    WAD := TWADFile.Create();
    if not WAD.ReadFile(FileName) then
    begin
      g_FatalError(Format(_lc[I_GAME_ERROR_MAP_WAD], [FileName]));
      WAD.Free();
      Exit;
    end;
    //k8: why loader ignores path here?
    mapResName := g_ExtractFileName(Res);
    if not WAD.GetMapResource(mapResName, Data, Len) then
    begin
      g_FatalError(Format(_lc[I_GAME_ERROR_MAP_RES], [mapResName]));
      WAD.Free();
      Exit;
    end;

    WAD.Free();

  // �������� �����:
    e_WriteLog('Loading map: '+mapResName, MSG_NOTIFY);
    g_Game_SetLoadingText(_lc[I_LOAD_MAP], 0, False);
    MapReader := TMapReader_1.Create();

    if not MapReader.LoadMap(Data) then
    begin
      g_FatalError(Format(_lc[I_GAME_ERROR_MAP_LOAD], [Res]));
      FreeMem(Data);
      MapReader.Free();
      Exit;
    end;

    FreeMem(Data);
    generateExternalResourcesList(MapReader);
  // �������� �������:
    g_Game_SetLoadingText(_lc[I_LOAD_TEXTURES], 0, False);
    _textures := MapReader.GetTextures();
    _texnummap := nil;

  // ���������� ������� � Textures[]:
    if _textures <> nil then
    begin
      e_WriteLog('  Loading textures:', MSG_NOTIFY);
      g_Game_SetLoadingText(_lc[I_LOAD_TEXTURES], High(_textures), False);
      SetLength(_texnummap, length(_textures));

      for a := 0 to High(_textures) do
      begin
        SetLength(s, 64);
        CopyMemory(@s[1], @_textures[a].Resource[0], 64);
        for b := 1 to Length(s) do
          if s[b] = #0 then
          begin
            SetLength(s, b-1);
            Break;
          end;
        e_WriteLog(Format('    Loading texture #%d: %s', [a, s]), MSG_NOTIFY);
        //if g_Map_IsSpecialTexture(s) then e_WriteLog('      SPECIAL!', MSG_NOTIFY);
      // ������������� ��������:
        if ByteBool(_textures[a].Anim) then
          begin
            ntn := CreateAnimTexture(_textures[a].Resource, FileName, True);
            if ntn < 0 then
            begin
              g_SimpleError(Format(_lc[I_GAME_ERROR_TEXTURE_ANIM], [s]));
              ntn := CreateNullTexture(_textures[a].Resource);
            end;
          end
        else // ������� ��������:
          ntn := CreateTexture(_textures[a].Resource, FileName, True);
          if ntn < 0 then
          begin
            g_SimpleError(Format(_lc[I_GAME_ERROR_TEXTURE_SIMPLE], [s]));
            ntn := CreateNullTexture(_textures[a].Resource);
          end;

        _texnummap[a] := ntn; // fix texture number
        g_Game_StepLoading();
      end;
    end;

  // �������� ���������:
    gTriggerClientID := 0;
    e_WriteLog('  Loading triggers...', MSG_NOTIFY);
    g_Game_SetLoadingText(_lc[I_LOAD_TRIGGERS], 0, False);
    triggers := MapReader.GetTriggers();

  // �������� �������:
    e_WriteLog('  Loading panels...', MSG_NOTIFY);
    g_Game_SetLoadingText(_lc[I_LOAD_PANELS], 0, False);
    panels := MapReader.GetPanels();

    // check texture numbers for panels
    for a := 0 to High(panels) do
    begin
      if panels[a].TextureNum > High(_textures) then
      begin
        e_WriteLog('error loading map: invalid texture index for panel', MSG_FATALERROR);
        result := false;
        exit;
      end;
      panels[a].TextureNum := _texnummap[panels[a].TextureNum];
    end;

  // �������� ������� ��������� (������������ ������� ���������):
    if triggers <> nil then
    begin
      e_WriteLog('  Setting up trigger table...', MSG_NOTIFY);
      SetLength(TriggersTable, Length(triggers));
      g_Game_SetLoadingText(_lc[I_LOAD_TRIGGERS_TABLE], High(TriggersTable), False);

      for a := 0 to High(TriggersTable) do
      begin
      // ����� �������� (��������, ������):
        TriggersTable[a].TexturePanel := triggers[a].TexturePanel;
      // �����:
        if triggers[a].TriggerType in [TRIGGER_LIFTUP, TRIGGER_LIFTDOWN, TRIGGER_LIFT] then
          TriggersTable[a].LiftPanel := TTriggerData(triggers[a].DATA).PanelID
        else
          TriggersTable[a].LiftPanel := -1;
      // �����:
        if triggers[a].TriggerType in [TRIGGER_OPENDOOR,
            TRIGGER_CLOSEDOOR, TRIGGER_DOOR, TRIGGER_DOOR5,
            TRIGGER_CLOSETRAP, TRIGGER_TRAP] then
          TriggersTable[a].DoorPanel := TTriggerData(triggers[a].DATA).PanelID
        else
          TriggersTable[a].DoorPanel := -1;
      // ������:
        if triggers[a].TriggerType = TRIGGER_SHOT then
          TriggersTable[a].ShotPanel := TTriggerData(triggers[a].DATA).ShotPanelID
        else
          TriggersTable[a].ShotPanel := -1;

        g_Game_StepLoading();
      end;
    end;

  // ������� ������:
    if panels <> nil then
    begin
      e_WriteLog('  Setting up trigger links...', MSG_NOTIFY);
      g_Game_SetLoadingText(_lc[I_LOAD_LINK_TRIGGERS], High(panels), False);

      for a := 0 to High(panels) do
      begin
        SetLength(AddTextures, 0);
        trigRef := False;
        CurTex := -1;
        if _textures <> nil then
          begin
            texture := _textures[panels[a].TextureNum];
            ok := True;
          end
        else
          ok := False;

        if ok then
        begin
        // �������, ��������� �� �� ��� ������ ��������.
        // ���� �� - �� ���� ������� ��� �������:
          ok := False;
          if (TriggersTable <> nil) and (_textures <> nil) then
            for b := 0 to High(TriggersTable) do
              if (TriggersTable[b].TexturePanel = a)
              or (TriggersTable[b].ShotPanel = a) then
              begin
                trigRef := True;
                ok := True;
                Break;
              end;
        end;

        if ok then
        begin // ���� ������ ��������� �� ��� ������
          SetLength(s, 64);
          CopyMemory(@s[1], @texture.Resource[0], 64);
        // �������� �����:
          Len := Length(s);
          for c := Len downto 1 do
            if s[c] <> #0 then
            begin
              Len := c;
              Break;
            end;
          SetLength(s, Len);

        // ����-�������� ���������:
          if g_Map_IsSpecialTexture(s) then
            ok := False
          else
        // ���������� ������� � ��������� ���� � ����� ������:
            ok := g_Texture_NumNameFindStart(s);

        // ���� ok, ������ ���� ����� � �����.
        // ��������� �������� � ���������� #:
          if ok then
          begin
            k := NNF_NAME_BEFORE;
          // ���� �� ��������� ����� ��������:
            while ok or (k = NNF_NAME_BEFORE) or
                  (k = NNF_NAME_EQUALS) do
            begin
              k := g_Texture_NumNameFindNext(TexName);

              if (k = NNF_NAME_BEFORE) or
                 (k = NNF_NAME_AFTER) then
                begin
                // ������� �������� ����� ��������:
                  if ByteBool(texture.Anim) then
                    begin // ��������� - �������������, ���� �������������
                      isAnim := True;
                      ok := CreateAnimTexture(TexName, FileName, False) >= 0;
                      if not ok then
                      begin // ��� �������������, ���� �������
                        isAnim := False;
                        ok := CreateTexture(TexName, FileName, False) >= 0;
                      end;
                    end
                  else
                    begin // ��������� - �������, ���� �������
                      isAnim := False;
                      ok := CreateTexture(TexName, FileName, False) >= 0;
                      if not ok then
                      begin // ��� �������, ���� �������������
                        isAnim := True;
                        ok := CreateAnimTexture(TexName, FileName, False) >= 0;
                      end;
                    end;

                // ��� ����������. ������� �� ID � ������ ������:
                  if ok then
                  begin
                    for c := 0 to High(Textures) do
                      if Textures[c].TextureName = TexName then
                      begin
                        SetLength(AddTextures, Length(AddTextures)+1);
                        AddTextures[High(AddTextures)].Texture := c;
                        AddTextures[High(AddTextures)].Anim := isAnim;
                        Break;
                      end;
                  end;
                end
              else
                if k = NNF_NAME_EQUALS then
                  begin
                  // ������� ������� �������� �� ���� �����:
                    SetLength(AddTextures, Length(AddTextures)+1);
                    AddTextures[High(AddTextures)].Texture := panels[a].TextureNum;
                    AddTextures[High(AddTextures)].Anim := ByteBool(texture.Anim);
                    CurTex := High(AddTextures);
                    ok := True;
                  end
                else // NNF_NO_NAME
                  ok := False;
            end; // while ok...

            ok := True;
          end; // if ok - ���� ������� ��������
        end; // if ok - ��������� ��������

        if not ok then
        begin
        // ������� ������ ������� ��������:
          SetLength(AddTextures, 1);
          AddTextures[0].Texture := panels[a].TextureNum;
          AddTextures[0].Anim := ByteBool(texture.Anim);
          CurTex := 0;
        end;

        //e_WriteLog(Format('panel #%d: TextureNum=%d; ht=%d; ht1=%d; atl=%d', [a, panels[a].TextureNum, High(_textures), High(Textures), High(AddTextures)]), MSG_NOTIFY);

      // ������� ������ � ���������� �� �����:
        PanelID := CreatePanel(panels[a], AddTextures, CurTex, trigRef);

      // ���� ������������ � ���������, �� ������ ������ ID:
        if TriggersTable <> nil then
          for b := 0 to High(TriggersTable) do
          begin
          // ������� �����/�����:
            if (TriggersTable[b].LiftPanel = a) or
               (TriggersTable[b].DoorPanel = a) then
              TTriggerData(triggers[b].DATA).PanelID := PanelID;
          // ������� ����� ��������:
            if TriggersTable[b].TexturePanel = a then
              triggers[b].TexturePanel := PanelID;
          // ������� "������":
            if TriggersTable[b].ShotPanel = a then
              TTriggerData(triggers[b].DATA).ShotPanelID := PanelID;
          end;

        g_Game_StepLoading();
      end;
    end;

  // ���� �� LoadState, �� ������� ��������:
    if (triggers <> nil) and not gLoadGameMode then
    begin
      e_WriteLog('  Creating triggers...', MSG_NOTIFY);
      g_Game_SetLoadingText(_lc[I_LOAD_CREATE_TRIGGERS], 0, False);
    // ��������� ��� ������, ���� ����:
      for a := 0 to High(triggers) do
      begin
        if triggers[a].TexturePanel <> -1 then
          b := panels[TriggersTable[a].TexturePanel].PanelType
        else
          b := 0;
        if (triggers[a].TriggerType = TRIGGER_SHOT) and
           (TTriggerData(triggers[a].DATA).ShotPanelID <> -1) then
          c := panels[TriggersTable[a].ShotPanel].PanelType
        else
          c := 0;
        CreateTrigger(triggers[a], b, c);
      end;
    end;

  // �������� ���������:
    e_WriteLog('  Loading triggers...', MSG_NOTIFY);
    g_Game_SetLoadingText(_lc[I_LOAD_ITEMS], 0, False);
    items := MapReader.GetItems();

  // ���� �� LoadState, �� ������� ��������:
    if (items <> nil) and not gLoadGameMode then
    begin
      e_WriteLog('  Spawning items...', MSG_NOTIFY);
      g_Game_SetLoadingText(_lc[I_LOAD_CREATE_ITEMS], 0, False);
      for a := 0 to High(items) do
        CreateItem(Items[a]);
    end;

  // �������� ��������:
    e_WriteLog('  Loading areas...', MSG_NOTIFY);
    g_Game_SetLoadingText(_lc[I_LOAD_AREAS], 0, False);
    areas := MapReader.GetAreas();

  // ���� �� LoadState, �� ������� �������:
    if areas <> nil then
    begin
      e_WriteLog('  Creating areas...', MSG_NOTIFY);
      g_Game_SetLoadingText(_lc[I_LOAD_CREATE_AREAS], 0, False);
      for a := 0 to High(areas) do
        CreateArea(areas[a]);
    end;

  // �������� ��������:
    e_WriteLog('  Loading monsters...', MSG_NOTIFY);
    g_Game_SetLoadingText(_lc[I_LOAD_MONSTERS], 0, False);
    monsters := MapReader.GetMonsters();

    gTotalMonsters := 0;

  // ���� �� LoadState, �� ������� ��������:
    if (monsters <> nil) and not gLoadGameMode then
    begin
      e_WriteLog('  Spawning monsters...', MSG_NOTIFY);
      g_Game_SetLoadingText(_lc[I_LOAD_CREATE_MONSTERS], 0, False);
      for a := 0 to High(monsters) do
        CreateMonster(monsters[a]);
    end;

  // �������� �������� �����:
    e_WriteLog('  Reading map info...', MSG_NOTIFY);
    g_Game_SetLoadingText(_lc[I_LOAD_MAP_HEADER], 0, False);
    Header := MapReader.GetMapHeader();

    MapReader.Free();

    with gMapInfo do
    begin
      Name := Header.MapName;
      Description := Header.MapDescription;
      Author := Header.MapAuthor;
      MusicName := Header.MusicName;
      SkyName := Header.SkyName;
      Height := Header.Height;
      Width := Header.Width;
    end;

  // �������� ����:
    if gMapInfo.SkyName <> '' then
    begin
      e_WriteLog('  Loading sky: ' + gMapInfo.SkyName, MSG_NOTIFY);
      g_Game_SetLoadingText(_lc[I_LOAD_SKY], 0, False);
      FileName := g_ExtractWadName(gMapInfo.SkyName);

      if FileName <> '' then
        FileName := GameDir+'/wads/'+FileName
      else
        begin
          FileName := g_ExtractWadName(Res);
        end;

      s := FileName+':'+g_ExtractFilePathName(gMapInfo.SkyName);
      if g_Texture_CreateWAD(BackID, s) then
        begin
          g_Game_SetupScreenSize();
        end
      else
        g_FatalError(Format(_lc[I_GAME_ERROR_SKY], [s]));
    end;

  // �������� ������:
    ok := False;
    if gMapInfo.MusicName <> '' then
    begin
      e_WriteLog('  Loading music: ' + gMapInfo.MusicName, MSG_NOTIFY);
      g_Game_SetLoadingText(_lc[I_LOAD_MUSIC], 0, False);
      FileName := g_ExtractWadName(gMapInfo.MusicName);

      if FileName <> '' then
        FileName := GameDir+'/wads/'+FileName
      else
        begin
          FileName := g_ExtractWadName(Res);
        end;

      s := FileName+':'+g_ExtractFilePathName(gMapInfo.MusicName);
      if g_Sound_CreateWADEx(gMapInfo.MusicName, s, True) then
        ok := True
      else
        g_FatalError(Format(_lc[I_GAME_ERROR_MUSIC], [s]));
    end;

  // ��������� ��������:
    CreateDoorMap();
    CreateLiftMap();

    g_Items_Init();
    g_Weapon_Init();
    g_Monsters_Init();

  // ���� �� LoadState, �� ������� ����� ������������:
    if not gLoadGameMode then
      g_GFX_Init();

  // ����� ��������� ��������:
    _textures := nil;
    panels := nil;
    items := nil;
    areas := nil;
    triggers := nil;
    TriggersTable := nil;
    AddTextures := nil;

  // �������� ������, ���� ��� �� ��������:
    if ok and (not gLoadGameMode) then
      begin
        gMusic.SetByName(gMapInfo.MusicName);
        gMusic.Play();
      end
    else
      gMusic.SetByName('');
  finally
    sfsGCEnable(); // enable releasing unused volumes
  end;

  e_WriteLog('Done loading map.', MSG_NOTIFY);
  Result := True;
end;

function g_Map_GetMapInfo(Res: String): TMapInfo;
var
  WAD: TWADFile;
  MapReader: TMapReader_1;
  Header: TMapHeaderRec_1;
  FileName: String;
  Data: Pointer;
  Len: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  FileName := g_ExtractWadName(Res);

  WAD := TWADFile.Create();
  if not WAD.ReadFile(FileName) then
  begin
    WAD.Free();
    Exit;
  end;

  //k8: it ignores path again
  if not WAD.GetMapResource(g_ExtractFileName(Res), Data, Len) then
  begin
    WAD.Free();
    Exit;
  end;

  WAD.Free();

  MapReader := TMapReader_1.Create();

  if not MapReader.LoadMap(Data) then
    begin
      g_Console_Add(Format(_lc[I_GAME_ERROR_MAP_LOAD], [Res]), True);
      ZeroMemory(@Header, SizeOf(Header));
      Result.Name := _lc[I_GAME_ERROR_MAP_SELECT];
      Result.Description := _lc[I_GAME_ERROR_MAP_SELECT];
    end
  else
    begin
      Header := MapReader.GetMapHeader();
      Result.Name := Header.MapName;
      Result.Description := Header.MapDescription;
    end;

  FreeMem(Data);
  MapReader.Free();

  Result.Map := Res;
  Result.Author := Header.MapAuthor;
  Result.Height := Header.Height;
  Result.Width := Header.Width;
end;

function g_Map_GetMapsList(WADName: string): SArray;
var
  WAD: TWADFile;
  a: Integer;
  ResList: SArray;
begin
  Result := nil;
  WAD := TWADFile.Create();
  if not WAD.ReadFile(WADName) then
  begin
    WAD.Free();
    Exit;
  end;
  ResList := WAD.GetMapResources();
  if ResList <> nil then
  begin
    for a := 0 to High(ResList) do
    begin
      SetLength(Result, Length(Result)+1);
      Result[High(Result)] := ResList[a];
    end;
  end;
  WAD.Free();
end;

function g_Map_Exist(Res: string): Boolean;
var
  WAD: TWADFile;
  FileName, mnn: string;
  ResList: SArray;
  a: Integer;
begin
  Result := False;

  FileName := addWadExtension(g_ExtractWadName(Res));

  WAD := TWADFile.Create;
  if not WAD.ReadFile(FileName) then
  begin
    WAD.Free();
    Exit;
  end;

  ResList := WAD.GetMapResources();
  WAD.Free();

  mnn := g_ExtractFileName(Res);
  if ResList <> nil then
    for a := 0 to High(ResList) do if StrEquCI1251(ResList[a], mnn) then
    begin
      Result := True;
      Exit;
    end;
end;

procedure g_Map_Free();
var
  a: Integer;

  procedure FreePanelArray(var panels: TPanelArray);
  var
    i: Integer;

  begin
    if panels <> nil then
    begin
      for i := 0 to High(panels) do
        panels[i].Free();
      panels := nil;
    end;
  end;

begin
  g_GFX_Free();
  g_Weapon_Free();
  g_Items_Free();
  g_Triggers_Free();
  g_Monsters_Free();

  RespawnPoints := nil;
  if FlagPoints[FLAG_RED] <> nil then
  begin
    Dispose(FlagPoints[FLAG_RED]);
    FlagPoints[FLAG_RED] := nil;
  end;
  if FlagPoints[FLAG_BLUE] <> nil then
  begin
    Dispose(FlagPoints[FLAG_BLUE]);
    FlagPoints[FLAG_BLUE] := nil;
  end;
  //DOMFlagPoints := nil;

  //gDOMFlags := nil;

  if Textures <> nil then
  begin
    for a := 0 to High(Textures) do
      if not g_Map_IsSpecialTexture(Textures[a].TextureName) then
        if Textures[a].Anim then
          g_Frames_DeleteByID(Textures[a].FramesID)
        else
          if Textures[a].TextureID <> TEXTURE_NONE then
            e_DeleteTexture(Textures[a].TextureID);

    Textures := nil;
  end;

  FreePanelArray(gWalls);
  FreePanelArray(gRenderBackgrounds);
  FreePanelArray(gRenderForegrounds);
  FreePanelArray(gWater);
  FreePanelArray(gAcid1);
  FreePanelArray(gAcid2);
  FreePanelArray(gSteps);
  FreePanelArray(gLifts);
  FreePanelArray(gBlockMon);

  if BackID <> DWORD(-1) then
  begin
    gBackSize.X := 0;
    gBackSize.Y := 0;
    e_DeleteTexture(BackID);
    BackID := DWORD(-1);
  end;

  g_Game_StopAllSounds(False);
  gMusic.FreeSound();
  g_Sound_Delete(gMapInfo.MusicName);

  gMapInfo.Name := '';
  gMapInfo.Description := '';
  gMapInfo.MusicName := '';
  gMapInfo.Height := 0;
  gMapInfo.Width := 0;

  gDoorMap := nil;
  gLiftMap := nil;

  PanelByID := nil;
end;

procedure g_Map_Update();
var
  a, d, j: Integer;
  m: Word;
  s: String;

  procedure UpdatePanelArray(var panels: TPanelArray);
  var
    i: Integer;

  begin
    if panels <> nil then
      for i := 0 to High(panels) do
        panels[i].Update();
  end;

begin
  UpdatePanelArray(gWalls);
  UpdatePanelArray(gRenderBackgrounds);
  UpdatePanelArray(gRenderForegrounds);
  UpdatePanelArray(gWater);
  UpdatePanelArray(gAcid1);
  UpdatePanelArray(gAcid2);
  UpdatePanelArray(gSteps);

  if gGameSettings.GameMode = GM_CTF then
  begin
    for a := FLAG_RED to FLAG_BLUE do
      if not (gFlags[a].State in [FLAG_STATE_NONE, FLAG_STATE_CAPTURED]) then
        with gFlags[a] do
        begin
          if gFlags[a].Animation <> nil then
            gFlags[a].Animation.Update();

          m := g_Obj_Move(@Obj, True, True);

          if gTime mod (GAME_TICK*2) <> 0 then
            Continue;

        // ������������� �������:
          Obj.Vel.X := z_dec(Obj.Vel.X, 1);

        // ������� ����������� �����, ���� �� ����� �� �����:
          if ((Count = 0) or ByteBool(m and MOVE_FALLOUT)) and g_Game_IsServer then
          begin
            g_Map_ResetFlag(a);
            gFlags[a].CaptureTime := 0;
            if a = FLAG_RED then
              s := _lc[I_PLAYER_FLAG_RED]
            else
              s := _lc[I_PLAYER_FLAG_BLUE];
            g_Game_Message(Format(_lc[I_MESSAGE_FLAG_RETURN], [AnsiUpperCase(s)]), 144);

            if g_Game_IsNet then
              MH_SEND_FlagEvent(FLAG_STATE_RETURNED, a, 0);
            Continue;
          end;

          if Count > 0 then
            Count := Count - 1;

        // ����� ����� ����:
          if gPlayers <> nil then
          begin
            j := Random(Length(gPlayers)) - 1;

            for d := 0 to High(gPlayers) do
            begin
              Inc(j);
              if j > High(gPlayers) then
                j := 0;

              if gPlayers[j] <> nil then
                if gPlayers[j].Live and
                   g_Obj_Collide(@Obj, @gPlayers[j].Obj) then
                begin
                  if gPlayers[j].GetFlag(a) then
                    Break;
                end;
            end;
          end;
        end;
  end;
end;


var
  pvpset: array of PPanel = nil; // potentially lit panels
  pvpb, pvpe: array [0..7] of Integer; // start/end (inclusive) of the correspoinding type panels in pvpset
  pvpcount: Integer = -1; // to avoid constant reallocations

function pvpType (panelType: Word): Integer;
begin
  case panelType of
    PANEL_WALL, PANEL_CLOSEDOOR: result := 0; // gWalls
    PANEL_BACK: result := 1; // gRenderBackgrounds
    PANEL_FORE: result := 2; // gRenderForegrounds
    PANEL_WATER: result := 3; // gWater
    PANEL_ACID1: result := 4; // gAcid1
    PANEL_ACID2: result := 5; // gAcid2
    PANEL_STEP: result := 6; // gSteps
    else result := -1;
  end;
end;

procedure g_Map_ResetPVP ();
begin
  pvpcount := -1; // special
end;

procedure g_Map_BuildPVP (minx, miny, maxx, maxy: Integer);
var
  idx: Integer;
  tpc: Integer;

  procedure checkPanels (var panels: TPanelArray; stp: Integer);
  var
    idx, x, y, w, h: Integer;
  begin
    if panels = nil then exit;
    tpc := tpc+Length(panels);
    if (stp < 0) or (stp > 6) then exit;
    pvpb[stp] := pvpcount;
    for idx := 0 to High(panels) do
    begin
      w := panels[idx].Width;
      h := panels[idx].Height;
      if (w < 1) or (h < 1) then continue;
      x := panels[idx].X;
      y := panels[idx].Y;
      if (x > maxx) or (y > maxy) then continue;
      if (x+w <= minx) or (y+h <= miny) then continue;
      if pvpcount = length(pvpset) then SetLength(pvpset, pvpcount+32768);
      pvpset[pvpcount] := @panels[idx];
      Inc(pvpcount);
    end;
    pvpe[stp] := pvpcount-1;
  end;

begin
  //e_WriteLog(Format('visible rect: (%d,%d)-(%d,%d)', [minx, miny, maxx, maxy]), MSG_NOTIFY);
  pvpcount := 0;
  for idx := 0 to High(pvpb) do begin pvpb[idx] := 0; pvpe[idx] := -1; end;
  tpc := 0;
  checkPanels(gWalls, 0);
  checkPanels(gRenderBackgrounds, 1);
  checkPanels(gRenderForegrounds, 2);
  checkPanels(gWater, 3);
  checkPanels(gAcid1, 4);
  checkPanels(gAcid2, 5);
  checkPanels(gSteps, 6);
  //e_WriteLog(Format('total panels: %d; visible panels: %d', [tpc, pvpcount]), MSG_NOTIFY);
end;

procedure g_Map_DrawPanels(PanelType: Word);

  procedure DrawPanels (stp: Integer; var panels: TPanelArray; drawDoors: Boolean=False);
  var
    idx: Integer;
  begin
    if (panels <> nil) and (stp >= 0) and (stp <= 6) then
    begin
      if pvpcount < 0 then
      begin
        // alas, no visible set
        for idx := 0 to High(panels) do
        begin
          if not (drawDoors xor panels[idx].Door) then panels[idx].Draw();
        end;
      end
      else
      begin
        // wow, use visible set
        if pvpb[stp] <= pvpe[stp] then
        begin
          for idx := pvpb[stp] to pvpe[stp] do
          begin
            if not (drawDoors xor pvpset[idx].Door) then pvpset[idx].Draw();
          end;
        end;
      end;
    end;
  end;

begin
  case PanelType of
    PANEL_WALL:       DrawPanels(0, gWalls);
    PANEL_CLOSEDOOR:  DrawPanels(0, gWalls, True);
    PANEL_BACK:       DrawPanels(1, gRenderBackgrounds);
    PANEL_FORE:       DrawPanels(2, gRenderForegrounds);
    PANEL_WATER:      DrawPanels(3, gWater);
    PANEL_ACID1:      DrawPanels(4, gAcid1);
    PANEL_ACID2:      DrawPanels(5, gAcid2);
    PANEL_STEP:       DrawPanels(6, gSteps);
  end;
end;

var
  plpset: array of Integer = nil; // potentially lit panels
  plpcount: Integer; // to avoid constant reallocations

function g_Map_BuildPLP (ltminx, ltminy, ltmaxx, ltmaxy: Integer): Boolean;
var
  idx: Integer;
  panels: TPanelArray;
begin
  panels := gWalls;
  plpcount := 0;
  if (ltminx < ltmaxx) and (ltminy < ltmaxy) then
  begin
    if panels <> nil then
    begin
      for idx := 0 to High(panels) do
      begin
        if (panels[idx].Width < 1) or (panels[idx].Height < 1) then continue;
        if (panels[idx].X+panels[idx].Width <= ltminx) then continue;
        if (panels[idx].Y+panels[idx].Height <= ltminy) then continue;
        if (panels[idx].X > ltmaxx) then continue;
        if (panels[idx].Y > ltmaxy) then continue;
        if plpcount = length(plpset) then SetLength(plpset, plpcount+32768);
        plpset[plpcount] := idx;
        Inc(plpcount);
      end;
      //e_WriteLog(Format('%d panels left out of %d', [plpcount, Length(panels)]), MSG_NOTIFY);
    end;
  end;
  result := (plpcount > 0);
end;

procedure g_Map_DrawPanelShadowVolumes(lightX: Integer; lightY: Integer; radius: Integer);

  (* old
  procedure drawPanels (var panels: TPanelArray);
  var
    a: Integer;
  begin
    if panels <> nil then
    begin
      for a := 0 to High(panels) do
      begin
        panels[a].DrawShadowVolume(lightX, lightY, radius);
      end;
    end;
  end;
  *)
var
  idx: Integer;
begin
  (*
  drawPanels(gWalls);
  //drawPanels(gRenderForegrounds);
  *)
  for idx := 0 to plpcount-1 do
  begin
    gWalls[plpset[idx]].DrawShadowVolume(lightX, lightY, radius);
  end;
end;

procedure g_Map_DrawBack(dx, dy: Integer);
begin
  if gDrawBackGround and (BackID <> DWORD(-1)) then
    e_DrawSize(BackID, dx, dy, 0, False, False, gBackSize.X, gBackSize.Y)
  else
    e_Clear(GL_COLOR_BUFFER_BIT, 0, 0, 0);
end;

function g_Map_CollidePanel(X, Y: Integer; Width, Height: Word;
                            PanelType: Word; b1x3: Boolean): Boolean;
var
  a, h: Integer;
begin
 Result := False;

 if WordBool(PanelType and PANEL_WALL) then
    if gWalls <> nil then
    begin
      h := High(gWalls);

      for a := 0 to h do
        if gWalls[a].Enabled and
        g_Collide(X, Y, Width, Height,
                  gWalls[a].X, gWalls[a].Y,
                  gWalls[a].Width, gWalls[a].Height) then
        begin
          Result := True;
          Exit;
        end;
    end;

  if WordBool(PanelType and PANEL_WATER) then
    if gWater <> nil then
    begin
      h := High(gWater);

      for a := 0 to h do
      if g_Collide(X, Y, Width, Height,
                   gWater[a].X, gWater[a].Y,
                   gWater[a].Width, gWater[a].Height) then
      begin
        Result := True;
        Exit;
      end;
    end;

  if WordBool(PanelType and PANEL_ACID1) then
    if gAcid1 <> nil then
    begin
      h := High(gAcid1);

      for a := 0 to h do
        if g_Collide(X, Y, Width, Height,
                     gAcid1[a].X, gAcid1[a].Y,
                     gAcid1[a].Width, gAcid1[a].Height) then
        begin
          Result := True;
          Exit;
        end;
    end;

  if WordBool(PanelType and PANEL_ACID2) then
    if gAcid2 <> nil then
    begin
      h := High(gAcid2);

      for a := 0 to h do
        if g_Collide(X, Y, Width, Height,
                     gAcid2[a].X, gAcid2[a].Y,
                     gAcid2[a].Width, gAcid2[a].Height) then
        begin
          Result := True;
          Exit;
        end;
    end;

  if WordBool(PanelType and PANEL_STEP) then
    if gSteps <> nil then
    begin
      h := High(gSteps);

      for a := 0 to h do
        if g_Collide(X, Y, Width, Height,
                     gSteps[a].X, gSteps[a].Y,
                     gSteps[a].Width, gSteps[a].Height) then
        begin
          Result := True;
          Exit;
        end;
    end;

  if WordBool(PanelType and (PANEL_LIFTUP or PANEL_LIFTDOWN or PANEL_LIFTLEFT or PANEL_LIFTRIGHT)) then
    if gLifts <> nil then
    begin
      h := High(gLifts);

      for a := 0 to h do
        if ((WordBool(PanelType and (PANEL_LIFTUP)) and (gLifts[a].LiftType = 0)) or
           (WordBool(PanelType and (PANEL_LIFTDOWN)) and (gLifts[a].LiftType = 1)) or
           (WordBool(PanelType and (PANEL_LIFTLEFT)) and (gLifts[a].LiftType = 2)) or
           (WordBool(PanelType and (PANEL_LIFTRIGHT)) and (gLifts[a].LiftType = 3))) and
           g_Collide(X, Y, Width, Height,
           gLifts[a].X, gLifts[a].Y,
           gLifts[a].Width, gLifts[a].Height) then
        begin
          Result := True;
          Exit;
        end;
    end;

  if WordBool(PanelType and PANEL_BLOCKMON) then
    if gBlockMon <> nil then
    begin
      h := High(gBlockMon);

      for a := 0 to h do
        if ( (not b1x3) or
             ((gBlockMon[a].Width + gBlockMon[a].Height) >= 64) ) and
           g_Collide(X, Y, Width, Height,
           gBlockMon[a].X, gBlockMon[a].Y,
           gBlockMon[a].Width, gBlockMon[a].Height) then
        begin
          Result := True;
          Exit;
        end;
    end;
end;

function g_Map_CollideLiquid_Texture(X, Y: Integer; Width, Height: Word): DWORD;
var
  a, h: Integer;
begin
  Result := TEXTURE_NONE;

  if gWater <> nil then
  begin
    h := High(gWater);

    for a := 0 to h do
      if g_Collide(X, Y, Width, Height,
                   gWater[a].X, gWater[a].Y,
                   gWater[a].Width, gWater[a].Height) then
      begin
        Result := gWater[a].GetTextureID();
        Exit;
      end;
  end;

  if gAcid1 <> nil then
  begin
    h := High(gAcid1);

    for a := 0 to h do
      if g_Collide(X, Y, Width, Height,
                   gAcid1[a].X, gAcid1[a].Y,
                   gAcid1[a].Width, gAcid1[a].Height) then
      begin
        Result := gAcid1[a].GetTextureID();
        Exit;
      end;
  end;

  if gAcid2 <> nil then
  begin
    h := High(gAcid2);

    for a := 0 to h do
      if g_Collide(X, Y, Width, Height,
                   gAcid2[a].X, gAcid2[a].Y,
                   gAcid2[a].Width, gAcid2[a].Height) then
      begin
        Result := gAcid2[a].GetTextureID();
        Exit;
      end;
  end;
end;

procedure g_Map_EnableWall(ID: DWORD);
begin
  with gWalls[ID] do
  begin
    Enabled := True;
    g_Mark(X, Y, Width, Height, MARK_DOOR, True);

    if g_Game_IsServer and g_Game_IsNet then MH_SEND_PanelState(PanelType, ID);
  end;
end;

procedure g_Map_DisableWall(ID: DWORD);
begin
  with gWalls[ID] do
  begin
    Enabled := False;
    g_Mark(X, Y, Width, Height, MARK_DOOR, False);

    if g_Game_IsServer and g_Game_IsNet then MH_SEND_PanelState(PanelType, ID);
  end;
end;

procedure g_Map_SwitchTexture(PanelType: Word; ID: DWORD; AnimLoop: Byte = 0);
var
  tp: TPanel;
begin
  case PanelType of
    PANEL_WALL, PANEL_OPENDOOR, PANEL_CLOSEDOOR:
      tp := gWalls[ID];
    PANEL_FORE:
      tp := gRenderForegrounds[ID];
    PANEL_BACK:
      tp := gRenderBackgrounds[ID];
    PANEL_WATER:
      tp := gWater[ID];
    PANEL_ACID1:
      tp := gAcid1[ID];
    PANEL_ACID2:
      tp := gAcid2[ID];
    PANEL_STEP:
      tp := gSteps[ID];
    else
      Exit;
  end;

  tp.NextTexture(AnimLoop);
  if g_Game_IsServer and g_Game_IsNet then
    MH_SEND_PanelTexture(PanelType, ID, AnimLoop);
end;

procedure g_Map_SetLift(ID: DWORD; t: Integer);
begin
  if gLifts[ID].LiftType = t then
    Exit;

  with gLifts[ID] do
  begin
    LiftType := t;

    g_Mark(X, Y, Width, Height, MARK_LIFT, False);

    if LiftType = 0 then
      g_Mark(X, Y, Width, Height, MARK_LIFTUP, True)
    else if LiftType = 1 then
      g_Mark(X, Y, Width, Height, MARK_LIFTDOWN, True)
    else if LiftType = 2 then
      g_Mark(X, Y, Width, Height, MARK_LIFTLEFT, True)
    else if LiftType = 3 then
      g_Mark(X, Y, Width, Height, MARK_LIFTRIGHT, True);

    if g_Game_IsServer and g_Game_IsNet then MH_SEND_PanelState(PanelType, ID);
  end;
end;

function g_Map_GetPoint(PointType: Byte; var RespawnPoint: TRespawnPoint): Boolean;
var
  a: Integer;
  PointsArray: Array of TRespawnPoint;
begin
  Result := False;
  SetLength(PointsArray, 0);

  if RespawnPoints = nil then
    Exit;

  for a := 0 to High(RespawnPoints) do
    if RespawnPoints[a].PointType = PointType then
    begin
      SetLength(PointsArray, Length(PointsArray)+1);
      PointsArray[High(PointsArray)] := RespawnPoints[a];
    end;

  if PointsArray = nil then
    Exit;

  RespawnPoint := PointsArray[Random(Length(PointsArray))];
  Result := True;
end;

function g_Map_GetPointCount(PointType: Byte): Word;
var
  a: Integer;
begin
  Result := 0;

  if RespawnPoints = nil then
    Exit;

  for a := 0 to High(RespawnPoints) do
    if RespawnPoints[a].PointType = PointType then
      Result := Result + 1;
end;

function g_Map_HaveFlagPoints(): Boolean;
begin
  Result := (FlagPoints[FLAG_RED] <> nil) and (FlagPoints[FLAG_BLUE] <> nil);
end;

procedure g_Map_ResetFlag(Flag: Byte);
begin
  with gFlags[Flag] do
  begin
    Obj.X := -1000;
    Obj.Y := -1000;
    Obj.Vel.X := 0;
    Obj.Vel.Y := 0;
    Direction := D_LEFT;
    State := FLAG_STATE_NONE;
    if FlagPoints[Flag] <> nil then
    begin
      Obj.X := FlagPoints[Flag]^.X;
      Obj.Y := FlagPoints[Flag]^.Y;
      Direction := FlagPoints[Flag]^.Direction;
      State := FLAG_STATE_NORMAL;
    end;
    Count := -1;
  end;
end;

procedure g_Map_DrawFlags();
var
  i, dx: Integer;
  Mirror: TMirrorType;
begin
  if gGameSettings.GameMode <> GM_CTF then
    Exit;

  for i := FLAG_RED to FLAG_BLUE do
    with gFlags[i] do
      if State <> FLAG_STATE_CAPTURED then
      begin
        if State = FLAG_STATE_NONE then
          continue;

        if Direction = D_LEFT then
          begin
            Mirror := M_HORIZONTAL;
            dx := -1;
          end
        else
          begin
            Mirror := M_NONE;
            dx := 1;
          end;

        Animation.Draw(Obj.X+dx, Obj.Y+1, Mirror);

        if g_debug_Frames then
        begin
          e_DrawQuad(Obj.X+Obj.Rect.X,
                     Obj.Y+Obj.Rect.Y,
                     Obj.X+Obj.Rect.X+Obj.Rect.Width-1,
                     Obj.Y+Obj.Rect.Y+Obj.Rect.Height-1,
                     0, 255, 0);
        end;
      end;
end;

procedure g_Map_SaveState(Var Mem: TBinMemoryWriter);
var
  dw: DWORD;
  b: Byte;
  str: String;
  boo: Boolean;

  procedure SavePanelArray(var panels: TPanelArray);
  var
    PAMem: TBinMemoryWriter;
    i: Integer;
  begin
  // ������� ����� ������ ����������� �������:
    PAMem := TBinMemoryWriter.Create((Length(panels)+1) * 40);

    i := 0;
    while i < Length(panels) do
    begin
      if panels[i].SaveIt then
      begin
      // ID ������:
        PAMem.WriteInt(i);
      // ��������� ������:
        panels[i].SaveState(PAMem);
      end;
      Inc(i);
    end;

  // ��������� ���� ������ �������:
    PAMem.SaveToMemory(Mem);
    PAMem.Free();
  end;

  procedure SaveFlag(flag: PFlag);
  begin
  // ��������� �����:
    dw := FLAG_SIGNATURE; // 'FLAG'
    Mem.WriteDWORD(dw);
  // ����� ������������� �����:
    Mem.WriteByte(flag^.RespawnType);
  // ��������� �����:
    Mem.WriteByte(flag^.State);
  // ����������� �����:
    if flag^.Direction = D_LEFT then
      b := 1
    else // D_RIGHT
      b := 2;
    Mem.WriteByte(b);
  // ������ �����:
    Obj_SaveState(@flag^.Obj, Mem);
  end;

begin
  Mem := TBinMemoryWriter.Create(1024 * 1024); // 1 MB

///// ��������� ������ �������: /////
// ��������� ������ ���� � ������:
  SavePanelArray(gWalls);
// ��������� ������ ����:
  SavePanelArray(gRenderBackgrounds);
// ��������� ������ ��������� �����:
  SavePanelArray(gRenderForegrounds);
// ��������� ������ ����:
  SavePanelArray(gWater);
// ��������� ������ �������-1:
  SavePanelArray(gAcid1);
// ��������� ������ �������-2:
  SavePanelArray(gAcid2);
// ��������� ������ ��������:
  SavePanelArray(gSteps);
// ��������� ������ ������:
  SavePanelArray(gLifts);
///// /////

///// ��������� ������: /////
// ��������� ������:
  dw := MUSIC_SIGNATURE; // 'MUSI'
  Mem.WriteDWORD(dw);
// �������� ������:
  Assert(gMusic <> nil, 'g_Map_SaveState: gMusic = nil');
  if gMusic.NoMusic then
    str := ''
  else
    str := gMusic.Name;
  Mem.WriteString(str, 64);
// ������� ������������ ������:
  dw := gMusic.GetPosition();
  Mem.WriteDWORD(dw);
// ����� �� ������ �� ����-�����:
  boo := gMusic.SpecPause;
  Mem.WriteBoolean(boo);
///// /////

///// ��������� ���������� ��������: /////
  Mem.WriteInt(gTotalMonsters);
///// /////

//// ��������� �����, ���� ��� CTF: /////
  if gGameSettings.GameMode = GM_CTF then
  begin
  // ���� ������� �������:
    SaveFlag(@gFlags[FLAG_RED]);
  // ���� ����� �������:
    SaveFlag(@gFlags[FLAG_BLUE]);
  end;
///// /////

///// ��������� ���������� �����, ���� ��� TDM/CTF: /////
  if gGameSettings.GameMode in [GM_TDM, GM_CTF] then
  begin
  // ���� ������� �������:
    Mem.WriteSmallInt(gTeamStat[TEAM_RED].Goals);
  // ���� ����� �������:
    Mem.WriteSmallInt(gTeamStat[TEAM_BLUE].Goals);
  end;
///// /////
end;

procedure g_Map_LoadState(Var Mem: TBinMemoryReader);
var
  dw: DWORD;
  b: Byte;
  str: String;
  boo: Boolean;

  procedure LoadPanelArray(var panels: TPanelArray);
  var
    PAMem: TBinMemoryReader;
    i, id: Integer;
  begin
  // ��������� ������� ������ �������:
    PAMem := TBinMemoryReader.Create();
    PAMem.LoadFromMemory(Mem);

    for i := 0 to Length(panels)-1 do
      if panels[i].SaveIt then
      begin
      // ID ������:
        PAMem.ReadInt(id);
        if id <> i then
        begin
          raise EBinSizeError.Create('g_Map_LoadState: LoadPanelArray: Wrong Panel ID');
        end;
      // ��������� ������:
        panels[i].LoadState(PAMem);
      end;

  // ���� ������ ������� ��������:
    PAMem.Free();
  end;

  procedure LoadFlag(flag: PFlag);
  begin
  // ��������� �����:
    Mem.ReadDWORD(dw);
    if dw <> FLAG_SIGNATURE then // 'FLAG'
    begin
      raise EBinSizeError.Create('g_Map_LoadState: LoadFlag: Wrong Flag Signature');
    end;
  // ����� ������������� �����:
    Mem.ReadByte(flag^.RespawnType);
  // ��������� �����:
    Mem.ReadByte(flag^.State);
  // ����������� �����:
    Mem.ReadByte(b);
    if b = 1 then
      flag^.Direction := D_LEFT
    else // b = 2
      flag^.Direction := D_RIGHT;
  // ������ �����:
    Obj_LoadState(@flag^.Obj, Mem);
  end;

begin
  if Mem = nil then
    Exit;

///// ��������� ������ �������: /////
// ��������� ������ ���� � ������:
  LoadPanelArray(gWalls);
// ��������� ������ ����:
  LoadPanelArray(gRenderBackgrounds);
// ��������� ������ ��������� �����:
  LoadPanelArray(gRenderForegrounds);
// ��������� ������ ����:
  LoadPanelArray(gWater);
// ��������� ������ �������-1:
  LoadPanelArray(gAcid1);
// ��������� ������ �������-2:
  LoadPanelArray(gAcid2);
// ��������� ������ ��������:
  LoadPanelArray(gSteps);
// ��������� ������ ������:
  LoadPanelArray(gLifts);
///// /////

// ��������� ����� ������������:
  g_GFX_Init();

///// ��������� ������: /////
// ��������� ������:
  Mem.ReadDWORD(dw);
  if dw <> MUSIC_SIGNATURE then // 'MUSI'
  begin
    raise EBinSizeError.Create('g_Map_LoadState: Wrong Music Signature');
  end;
// �������� ������:
  Assert(gMusic <> nil, 'g_Map_LoadState: gMusic = nil');
  Mem.ReadString(str);
// ������� ������������ ������:
  Mem.ReadDWORD(dw);
// ����� �� ������ �� ����-�����:
  Mem.ReadBoolean(boo);
// ��������� ��� ������:
  gMusic.SetByName(str);
  gMusic.SpecPause := boo;
  gMusic.Play();
  gMusic.Pause(True);
  gMusic.SetPosition(dw);
///// /////

///// ��������� ���������� ��������: /////
  Mem.ReadInt(gTotalMonsters);
///// /////

//// ��������� �����, ���� ��� CTF: /////
  if gGameSettings.GameMode = GM_CTF then
  begin
  // ���� ������� �������:
    LoadFlag(@gFlags[FLAG_RED]);
  // ���� ����� �������:
    LoadFlag(@gFlags[FLAG_BLUE]);
  end;
///// /////

///// ��������� ���������� �����, ���� ��� TDM/CTF: /////
  if gGameSettings.GameMode in [GM_TDM, GM_CTF] then
  begin
  // ���� ������� �������:
    Mem.ReadSmallInt(gTeamStat[TEAM_RED].Goals);
  // ���� ����� �������:
    Mem.ReadSmallInt(gTeamStat[TEAM_BLUE].Goals);
  end;
///// /////
end;

function g_Map_PanelForPID(PanelID: Integer; var PanelArrayID: Integer): PPanel;
var
  Arr: TPanelArray;
begin
  Result := nil;
  if (PanelID < 0) or (PanelID > High(PanelByID)) then Exit;
  Arr := PanelByID[PanelID].PWhere^;
  PanelArrayID := PanelByID[PanelID].PArrID;
  Result := Addr(Arr[PanelByID[PanelID].PArrID]);
end;

end.
