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
{$INCLUDE ../shared/a_modes.inc}
unit g_main;

interface

  uses Utils;

procedure Main ();
procedure Init ();
procedure Release ();
procedure Update ();
procedure Draw ();
procedure KeyPress (K: Word);
procedure CharPress (C: AnsiChar);

var
  {--- TO REMOVE ---}
  GameDir: string;
  {-----------------}

  {--- Read-only dirs ---}
  GameWAD: string;
  DataDirs: SSArray;
  ModelDirs: SSArray;
  MegawadDirs: SSArray;
  MapDirs: SSArray;
  WadDirs: SSArray;
  AllMapDirs: SSArray; // Maps + Megawads

  {--- Read-Write dirs ---}
  LogFileName: string;
  LogDirs: SSArray;
  SaveDirs: SSArray;
  CacheDirs: SSArray;
  ConfigDirs: SSArray;
  ScreenshotDirs: SSArray;
  MapDownloadDirs: SSArray;
  WadDownloadDirs: SSArray;

implementation

uses
{$INCLUDE ../nogl/noGLuses.inc}
{$IFDEF ENABLE_HOLMES}
  g_holmes, sdlcarcass, fui_ctls, fui_wadread, fui_style, fui_gfx_gl,
{$ENDIF}
  wadreader, e_log, g_window,
  e_graphics, e_input, g_game, g_console, g_gui,
  e_sound, g_options, g_sound, g_player, g_basic,
  g_weapons, SysUtils, g_triggers, MAPDEF, g_map, e_res,
  g_menu, g_language, g_net, g_touch, g_system, g_res_downloader,
  conbuf, envvars,
  xparser;


var
  charbuff: packed array [0..15] of AnsiChar;

procedure InitPath;
  var i: Integer; rwdir, rodir: AnsiString;

  procedure AddPath (var arr: SSArray; str: AnsiString);
  begin
    SetLength(arr, Length(arr) + 1);
    arr[High(arr)] := ExpandFileName(str)
  end;

  procedure AddDef (var arr: SSArray; str: AnsiString);
  begin
    if arr = nil then
      AddPath(arr, str)
  end;

begin
  GetDir(0, GameDir);

  i := 1;
  while i < ParamCount do
  begin
    case ParamStr(i) of
    '--rw-dir':
      begin
        Inc(i);
        rwdir := ParamStr(i);
        (* RW *)
        AddPath(LogDirs, e_CatPath(rwdir, ''));
        AddPath(SaveDirs, e_CatPath(rwdir, 'data'));
        AddPath(CacheDirs, e_CatPath(rwdir, 'data/cache'));
        AddPath(ConfigDirs, e_CatPath(rwdir, ''));
        AddPath(MapDownloadDirs, e_CatPath(rwdir, 'maps/downloads'));
        AddPath(WadDownloadDirs, e_CatPath(rwdir, 'wads/downloads'));
        AddPath(ScreenshotDirs, e_CatPath(rwdir, 'screenshots'));
        (* RO *)
        AddPath(DataDirs, e_CatPath(rwdir, 'data'));
        AddPath(ModelDirs, e_CatPath(rwdir, 'data/models'));
        AddPath(MegawadDirs, e_CatPath(rwdir, 'maps/megawads'));
        AddPath(MapDirs, e_CatPath(rwdir, 'maps'));
        AddPath(WadDirs, e_CatPath(rwdir, 'wads'));
      end;
    '--ro-dir':
      begin
        Inc(i);
        rodir := ParamStr(i);
        (* RO *)
        AddPath(DataDirs, e_CatPath(rodir, 'data'));
        AddPath(ModelDirs, e_CatPath(rodir, 'data/models'));
        AddPath(MegawadDirs, e_CatPath(rodir, 'maps/megawads'));
        AddPath(MapDirs, e_CatPath(rodir, 'maps'));
        AddPath(WadDirs, e_CatPath(rodir, 'wads'));
      end;
    end;
    Inc(i)
  end;

  (* RO *)
  AddDef(DataDirs, 'data');
  AddDef(ModelDirs, 'data/models');
  AddDef(MegawadDirs, 'maps/megawads');
  AddDef(MapDirs, 'maps');
  AddDef(WadDirs, 'wads');
  (* RW *)
  AddDef(LogDirs, '.');
  AddDef(SaveDirs, 'data');
  AddDef(CacheDirs, 'data/cache');
  AddDef(ConfigDirs, '.');
  AddDef(MapDownloadDirs, 'maps/downloads');
  AddDef(WadDownloadDirs, 'wad/downloads');
  AddDef(ScreenshotDirs, 'screenshots');

  for i := 0 to High(MapDirs) do
    AddPath(AllMapDirs, MapDirs[i]);
  for i := 0 to High(MegawadDirs) do
    AddPath(AllMapDirs, MegawadDirs[i]);

  if LogFileName = '' then
  begin
    rwdir := e_GetWriteableDir(LogDirs, false);
    if rwdir <> '' then
    begin
      {$IFDEF HEADLESS}
        LogFileName := e_CatPath(rwdir, 'Doom2DF_H.log');
      {$ELSE}
        LogFileName := e_Catpath(rwdir, 'Doom2DF.log');
      {$ENDIF}
    end
  end
end;

procedure Main();
{$IFDEF ENABLE_HOLMES}
  var flexloaded: Boolean;
{$ENDIF}
  var s: AnsiString;
begin
  InitPath;
  if LogFileName <> '' then
    e_InitLog(LogFileName, TWriteMode.WM_NEWFILE);
  e_InitWritelnDriver();

  GameWAD := e_FindWad(DataDirs, 'GAME');
  assert(GameWad <> '', 'GAME.WAD not installed?');


//  e_InitLog(GameDir + '/' + LogFileName, TWriteMode.WM_NEWFILE);

  e_WriteLog(
    'Doom 2D: Forever version ' + GAME_VERSION +
    ' proto ' + IntToStr(NET_PROTOCOL_VER),
    TMsgType.Notify
  );
  e_WriteLog(
    'Build date: ' + GAME_BUILDDATE + ' ' + GAME_BUILDTIME,
    TMsgType.Notify
  );

{$IFDEF HEADLESS}
  conbufDumpToStdOut := true;
{$ENDIF}
  e_WriteToStdOut := False; //{$IFDEF HEADLESS}True;{$ELSE}False;{$ENDIF}

  e_InitInput;

  sys_Init;

  s := CONFIG_FILENAME;
  if e_FindResource(ConfigDirs, s) = true then
  begin
    g_Options_Read(s)
  end
  else
  begin
    g_Options_SetDefault;
    g_Options_SetDefaultVideo
  end;
  if sys_SetDisplayMode(gScreenWidth, gScreenHeight, gBPP, gFullScreen) = False then
    raise Exception.Create('Failed to set videomode on startup.');

  g_Console_SysInit;
  e_WriteLog(gLanguage, TMsgType.Notify);
  g_Language_Set(gLanguage);

{$IF not DEFINED(HEADLESS) and DEFINED(ENABLE_HOLMES)}
  flexloaded := true;
  if not fuiAddWad('flexui.wad') then
  begin
    if not fuiAddWad('./data/flexui.wad') then fuiAddWad('./flexui.wad');
  end;
  try
    fuiGfxLoadFont('win8', 'flexui/fonts/win8.fuifont');
    fuiGfxLoadFont('win14', 'flexui/fonts/win14.fuifont');
    fuiGfxLoadFont('win16', 'flexui/fonts/win16.fuifont');
    fuiGfxLoadFont('dos8', 'flexui/fonts/dos8.fuifont');
    fuiGfxLoadFont('msx6', 'flexui/fonts/msx6.fuifont');
  except on e: Exception do
    begin
      writeln('ERROR loading FlexUI fonts');
      flexloaded := false;
      //raise;
    end;
  else
    begin
      flexloaded := false;
      //raise;
    end;
  end;
  if (flexloaded) then
  begin
    try
      e_LogWriteln('FlexUI: loading stylesheet...');
      uiLoadStyles('flexui/widgets.wgs');
    except on e: TParserException do
      begin
        writeln('ERROR at (', e.tokLine, ',', e.tokCol, '): ', e.message);
        //raise;
        flexloaded := false;
      end;
    else
      begin
        //raise;
        flexloaded := false;
      end;
    end;
  end;
  g_holmes_imfunctional := not flexloaded;

  if (not g_holmes_imfunctional) then
  begin
    uiInitialize();
    uiContext.font := 'win14';
  end;

  if assigned(oglInitCB) then oglInitCB;
{$ENDIF}

  //g_Res_CreateDatabases(); // it will be done before connecting to the server for the first time

  e_WriteLog('Entering SDLMain', TMsgType.Notify);

  {$WARNINGS OFF}
    SDLMain();
  {$WARNINGS ON}

  {$IFDEF ENABLE_HOLMES}
    if assigned(oglDeinitCB) then oglDeinitCB;
  {$ENDIF}

  sys_Final;
end;

procedure Init();
var
  NoSound: Boolean;
begin
  Randomize;

{$IFDEF HEADLESS}
 {$IFDEF USE_SDLMIXER}
  NoSound := False; // hope env has set SDL_AUDIODRIVER to dummy
 {$ELSE}
  NoSound := True; // FMOD backend will sort it out
 {$ENDIF}
{$ELSE}
  NoSound := False;
{$ENDIF}

  g_Touch_Init;

(*
  if (e_JoysticksAvailable > 0) then
    e_WriteLog('Input: Joysticks available.', TMsgType.Notify)
  else
    e_WriteLog('Input: No Joysticks.', TMsgType.Notify);
*)

  if (not gNoSound) then
  begin
    e_WriteLog('Initializing sound system', TMsgType.Notify);
    e_InitSoundSystem(NoSound);
  end;

  e_WriteLog('Init game', TMsgType.Notify);
  g_Game_Init();

  FillChar(charbuff, sizeof(charbuff), ' ');
end;


procedure Release();
begin
  e_WriteLog('Releasing engine', TMsgType.Notify);
  e_ReleaseEngine();

  e_WriteLog('Releasing input', TMsgType.Notify);
  e_ReleaseInput();

  if not gNoSound then
  begin
    e_WriteLog('Releasing sound', TMsgType.Notify);
    e_ReleaseSoundSystem();
  end;
end;


procedure Update ();
begin
  g_Game_Update();
end;


procedure Draw ();
begin
  g_Game_Draw();
end;


function Translit (const S: AnsiString): AnsiString;
var
  i: Integer;
begin
  Result := S;
  for i := 1 to Length(Result) do
  begin
    case Result[i] of
      '�': Result[i] := 'Q';
      '�': Result[i] := 'W';
      '�': Result[i] := 'E';
      '�': Result[i] := 'R';
      '�': Result[i] := 'T';
      '�': Result[i] := 'Y';
      '�': Result[i] := 'U';
      '�': Result[i] := 'I';
      '�': Result[i] := 'O';
      '�': Result[i] := 'P';
      '�': Result[i] := '['; //Chr(219);
      '�': Result[i] := ']'; //Chr(221);
      '�': Result[i] := 'A';
      '�': Result[i] := 'S';
      '�': Result[i] := 'D';
      '�': Result[i] := 'F';
      '�': Result[i] := 'G';
      '�': Result[i] := 'H';
      '�': Result[i] := 'J';
      '�': Result[i] := 'K';
      '�': Result[i] := 'L';
      '�': Result[i] := ';'; //Chr(186);
      '�': Result[i] := #39; //Chr(222);
      '�': Result[i] := 'Z';
      '�': Result[i] := 'X';
      '�': Result[i] := 'C';
      '�': Result[i] := 'V';
      '�': Result[i] := 'B';
      '�': Result[i] := 'N';
      '�': Result[i] := 'M';
      '�': Result[i] := ','; //Chr(188);
      '�': Result[i] := '.'; //Chr(190);
    end;
  end;
end;


function CheckCheat (ct: TStrings_Locale; eofs: Integer=0): Boolean;
var
  ls1, ls2: string;
begin
  ls1 :=          CheatEng[ct];
  ls2 := Translit(CheatRus[ct]);
  if length(ls1) = 0 then ls1 := '~';
  if length(ls2) = 0 then ls2 := '~';
  result :=
    (Copy(charbuff, 17-Length(ls1)-eofs, Length(ls1)) = ls1) or
    (Translit(Copy(charbuff, 17-Length(ls1)-eofs, Length(ls1))) = ls1) or
    (Copy(charbuff, 17-Length(ls2)-eofs, Length(ls2)) = ls2) or
    (Translit(Copy(charbuff, 17-Length(ls2)-eofs, Length(ls2))) = ls2);
  {
  if ct = I_GAME_CHEAT_JETPACK then
  begin
    e_WriteLog('ls1: ['+ls1+']', MSG_NOTIFY);
    e_WriteLog('ls2: ['+ls2+']', MSG_NOTIFY);
    e_WriteLog('bf0: ['+Copy(charbuff, 17-Length(ls1)-eofs, Length(ls1))+']', MSG_NOTIFY);
    e_WriteLog('bf1: ['+Translit(Copy(charbuff, 17-Length(ls1)-eofs, Length(ls1)))+']', MSG_NOTIFY);
    e_WriteLog('bf2: ['+Copy(charbuff, 17-Length(ls2)-eofs, Length(ls2))+']', MSG_NOTIFY);
    e_WriteLog('bf3: ['+Translit(Copy(charbuff, 17-Length(ls2)-eofs, Length(ls2)))+']', MSG_NOTIFY);
  end;
  }
end;


procedure Cheat ();
const
  CHEAT_DAMAGE = 500;
label
  Cheated;
var
  s, s2: string;
  c: ShortString;
  a: Integer;
begin
  {
  if (not gGameOn) or (not gCheats) or ((gGameSettings.GameType <> GT_SINGLE) and
    (gGameSettings.GameMode <> GM_COOP) and (not gDebugMode))
    or g_Game_IsNet then Exit;
  }
  if not gGameOn then exit;
  if not conIsCheatsEnabled then exit;

  s := 'SOUND_GAME_RADIO';

  //
  if CheckCheat(I_GAME_CHEAT_GODMODE) then
  begin
    if gPlayer1 <> nil then gPlayer1.GodMode := not gPlayer1.GodMode;
    if gPlayer2 <> nil then gPlayer2.GodMode := not gPlayer2.GodMode;
    goto Cheated;
  end;
  // RAMBO
  if CheckCheat(I_GAME_CHEAT_WEAPONS) then
  begin
    if gPlayer1 <> nil then gPlayer1.AllRulez(False);
    if gPlayer2 <> nil then gPlayer2.AllRulez(False);
    goto Cheated;
  end;
  // TANK
  if CheckCheat(I_GAME_CHEAT_HEALTH) then
  begin
    if gPlayer1 <> nil then gPlayer1.AllRulez(True);
    if gPlayer2 <> nil then gPlayer2.AllRulez(True);
    goto Cheated;
  end;
  // IDDQD
  if CheckCheat(I_GAME_CHEAT_DEATH) then
  begin
    if gPlayer1 <> nil then gPlayer1.Damage(CHEAT_DAMAGE, 0, 0, 0, HIT_TRAP);
    if gPlayer2 <> nil then gPlayer2.Damage(CHEAT_DAMAGE, 0, 0, 0, HIT_TRAP);
    s := 'SOUND_MONSTER_HAHA';
    goto Cheated;
  end;
  //
  if CheckCheat(I_GAME_CHEAT_DOORS) then
  begin
    g_Triggers_OpenAll();
    goto Cheated;
  end;
  // GOODBYE
  if CheckCheat(I_GAME_CHEAT_NEXTMAP) then
  begin
    if gTriggers <> nil then
      for a := 0 to High(gTriggers) do
        if gTriggers[a].TriggerType = TRIGGER_EXIT then
        begin
          gExitByTrigger := True;
          //g_Game_ExitLevel(gTriggers[a].Data.MapName);
          g_Game_ExitLevel(gTriggers[a].tgcMap);
          Break;
        end;
    goto Cheated;
  end;
  //
  s2 := Copy(charbuff, 15, 2);
  if CheckCheat(I_GAME_CHEAT_CHANGEMAP, 2) and (s2[1] >= '0') and (s2[1] <= '9') and (s2[2] >= '0') and (s2[2] <= '9') then
  begin
    if g_Map_Exist(gGameSettings.WAD + ':\MAP' + s2) then
    begin
      c := 'MAP' + s2;
      g_Game_ExitLevel(c);
    end;
    goto Cheated;
  end;
  //
  if CheckCheat(I_GAME_CHEAT_FLY) then
  begin
    gFly := not gFly;
    goto Cheated;
  end;
  // BULLFROG
  if CheckCheat(I_GAME_CHEAT_JUMPS) then
  begin
    VEL_JUMP := 30-VEL_JUMP;
    goto Cheated;
  end;
  // FORMULA1
  if CheckCheat(I_GAME_CHEAT_SPEED) then
  begin
    MAX_RUNVEL := 32-MAX_RUNVEL;
    goto Cheated;
  end;
  // CONDOM
  if CheckCheat(I_GAME_CHEAT_SUIT) then
  begin
    if gPlayer1 <> nil then gPlayer1.GiveItem(ITEM_SUIT);
    if gPlayer2 <> nil then gPlayer2.GiveItem(ITEM_SUIT);
    goto Cheated;
  end;
  //
  if CheckCheat(I_GAME_CHEAT_AIR) then
  begin
    if gPlayer1 <> nil then gPlayer1.GiveItem(ITEM_OXYGEN);
    if gPlayer2 <> nil then gPlayer2.GiveItem(ITEM_OXYGEN);
    goto Cheated;
  end;
  // PURELOVE
  if CheckCheat(I_GAME_CHEAT_BERSERK) then
  begin
    if gPlayer1 <> nil then gPlayer1.GiveItem(ITEM_MEDKIT_BLACK);
    if gPlayer2 <> nil then gPlayer2.GiveItem(ITEM_MEDKIT_BLACK);
    goto Cheated;
  end;
  //
  if CheckCheat(I_GAME_CHEAT_JETPACK) then
  begin
    if gPlayer1 <> nil then gPlayer1.GiveItem(ITEM_JETPACK);
    if gPlayer2 <> nil then gPlayer2.GiveItem(ITEM_JETPACK);
    goto Cheated;
  end;
  // CASPER
  if CheckCheat(I_GAME_CHEAT_NOCLIP) then
  begin
    if gPlayer1 <> nil then gPlayer1.SwitchNoClip;
    if gPlayer2 <> nil then gPlayer2.SwitchNoClip;
    goto Cheated;
  end;
  //
  if CheckCheat(I_GAME_CHEAT_NOTARGET) then
  begin
    if gPlayer1 <> nil then gPlayer1.NoTarget := not gPlayer1.NoTarget;
    if gPlayer2 <> nil then gPlayer2.NoTarget := not gPlayer2.NoTarget;
    goto Cheated;
  end;
  // INFERNO
  if CheckCheat(I_GAME_CHEAT_NORELOAD) then
  begin
    if gPlayer1 <> nil then gPlayer1.NoReload := not gPlayer1.NoReload;
    if gPlayer2 <> nil then gPlayer2.NoReload := not gPlayer2.NoReload;
    goto Cheated;
  end;
  if CheckCheat(I_GAME_CHEAT_AIMLINE) then
  begin
    gAimLine := not gAimLine;
    goto Cheated;
  end;
  if CheckCheat(I_GAME_CHEAT_AUTOMAP) then
  begin
    gShowMap := not gShowMap;
    goto Cheated;
  end;
  Exit;

Cheated:
  g_Sound_PlayEx(s);
end;


procedure KeyPress (K: Word);
{$IFNDEF HEADLESS}
var
  Msg: g_gui.TMessage;
{$ENDIF}
begin
{$IFNDEF HEADLESS}
  case K of
    VK_ESCAPE: // <Esc>:
      begin
        if (g_ActiveWindow <> nil) then
        begin
          Msg.Msg := WM_KEYDOWN;
          Msg.WParam := VK_ESCAPE;
          g_ActiveWindow.OnMessage(Msg);
          if (not g_Game_IsNet) and (g_ActiveWindow = nil) then g_Game_Pause(false); //Fn loves to do this
        end
        else if (gState <> STATE_FOLD) then
        begin
          if gGameOn or (gState = STATE_INTERSINGLE) or (gState = STATE_INTERCUSTOM) then
          begin
            g_Game_InGameMenu(True);
          end
          else if (gExit = 0) and (gState <> STATE_SLIST) then
          begin
            if (gState <> STATE_MENU) then
            begin
              if (NetMode <> NET_NONE) then
              begin
                g_Game_StopAllSounds(True);
                g_Game_Free;
                gState := STATE_MENU;
                Exit;
              end;
            end;
            g_GUI_ShowWindow('MainMenu');
            g_Sound_PlayEx('MENU_OPEN');
          end;
        end;
      end;

    IK_F2, IK_F3, IK_F4, IK_F5, IK_F6, IK_F7, IK_F10:
      begin // <F2> .. <F6> � <F12>
        if gGameOn and (not gConsoleShow) and (not gChatShow) then
        begin
          while (g_ActiveWindow <> nil) do g_GUI_HideWindow(False);
          if (not g_Game_IsNet) then g_Game_Pause(True);
          case K of
            IK_F2: g_Menu_Show_SaveMenu();
            IK_F3: g_Menu_Show_LoadMenu();
            IK_F4: g_Menu_Show_GameSetGame();
            IK_F5: g_Menu_Show_OptionsVideo();
            IK_F6: g_Menu_Show_OptionsSound();
            IK_F7: g_Menu_Show_EndGameMenu();
            IK_F10: g_Menu_Show_QuitGameMenu();
          end;
        end;
      end;

    else
      begin
        gJustChatted := False;
        if gConsoleShow or gChatShow then
        begin
          g_Console_Control(K);
        end
        else if (g_ActiveWindow <> nil) then
        begin
          Msg.Msg := WM_KEYDOWN;
          Msg.WParam := K;
          g_ActiveWindow.OnMessage(Msg);
        end
        else if (gState = STATE_MENU) then
        begin
          g_GUI_ShowWindow('MainMenu');
          g_Sound_PlayEx('MENU_OPEN');
        end;
      end;
  end;
{$ENDIF}
end;


procedure CharPress (C: AnsiChar);
var
  Msg: g_gui.TMessage;
  a: Integer;
begin
  if gConsoleShow or gChatShow then
  begin
    g_Console_Char(C)
  end
  else if (g_ActiveWindow <> nil) then
  begin
    Msg.Msg := WM_CHAR;
    Msg.WParam := Ord(C);
    g_ActiveWindow.OnMessage(Msg);
  end
  else
  begin
    for a := 0 to 14 do charbuff[a] := charbuff[a+1];
    charbuff[15] := upcase1251(C);
    Cheat();
  end;
end;

end.
