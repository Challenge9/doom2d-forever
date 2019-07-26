(* Copyright (C)  Doom 2D: Forever Developers
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
{$INCLUDE ../shared/a_modes.inc}
unit g_console;

interface

uses
  utils; // for SSArray

  const
    ACTION_JUMP = 0;
    ACTION_MOVELEFT = 1;
    ACTION_MOVERIGHT = 2;
    ACTION_LOOKDOWN = 3;
    ACTION_LOOKUP = 4;
    ACTION_ATTACK = 5;
    ACTION_SCORES = 6;
    ACTION_ACTIVATE = 7;
    ACTION_STRAFE = 8;
    ACTION_WEAPNEXT = 9;
    ACTION_WEAPPREV = 10;

    FIRST_ACTION = ACTION_JUMP;
    LAST_ACTION = ACTION_WEAPPREV;

procedure g_Console_Init;
procedure g_Console_Update;
procedure g_Console_Draw;
procedure g_Console_Char (C: AnsiChar);
procedure g_Console_Control (K: Word);
procedure g_Console_Process (L: AnsiString; quiet: Boolean=false);
procedure g_Console_Add (L: AnsiString; show: Boolean=false);
procedure g_Console_Clear;
function  g_Console_CommandBlacklisted (C: AnsiString): Boolean;
procedure g_Console_ReadConfig (filename: String);
procedure g_Console_WriteConfig (filename: String);
procedure g_Console_WriteGameConfig;

function  g_Console_Interactive: Boolean;
function  g_Console_Action (action: Integer): Boolean;
function  g_Console_MatchBind (key: Integer; down: AnsiString; up: AnsiString = ''): Boolean;
function  g_Console_FindBind (n: Integer; down: AnsiString; up: AnsiString = ''): Integer;
procedure g_Console_BindKey (key: Integer; down: AnsiString; up: AnsiString = '');
procedure g_Console_ProcessBind (key: Integer; down: Boolean);
procedure g_Console_ResetBinds;

procedure conwriteln (const s: AnsiString; show: Boolean=false);
procedure conwritefln (const s: AnsiString; args: array of const; show: Boolean=false);

procedure conRegVar (const conname: AnsiString; pvar: PBoolean; const ahelp: AnsiString; const amsg: AnsiString; acheat: Boolean=false; ahidden: Boolean=false); overload;
procedure conRegVar (const conname: AnsiString; pvar: PSingle; amin, amax: Single; const ahelp: AnsiString; const amsg: AnsiString; acheat: Boolean=false; ahidden: Boolean=false); overload;
procedure conRegVar (const conname: AnsiString; pvar: PInteger; const ahelp: AnsiString; const amsg: AnsiString; acheat: Boolean=false; ahidden: Boolean=false); overload;

// <0: no arg; 0/1: true/false
function conGetBoolArg (p: SSArray; idx: Integer): Integer;

// poor man's floating literal parser; i'm sorry, but `StrToFloat()` sux cocks
function conParseFloat (var res: Single; const s: AnsiString): Boolean;


var
  gConsoleShow: Boolean = false; // True - ������� ������� ��� �����������
  gChatShow: Boolean = false;
  gChatTeam: Boolean = false;
  gAllowConsoleMessages: Boolean = true;
  gJustChatted: Boolean = false; // ����� ����� � ������ ������ �� ���������� ����������
  gParsingBinds: Boolean = false; // �� ������������� ������ �� ����� ��������
  gPlayerAction: Array [0..1, 0..LAST_ACTION] of Boolean; // [player, action]

implementation

uses
  g_textures, g_main, e_graphics, e_input, g_game,
  SysUtils, g_basic, g_options, Math, g_touch,
  g_menu, g_gui, g_language, g_net, g_netmsg, e_log, conbuf;


type
  PCommand = ^TCommand;

  TCmdProc = procedure (p: SSArray);
  TCmdProcEx = procedure (me: PCommand; p: SSArray);

  TCommand = record
    cmd: AnsiString;
    proc: TCmdProc;
    procEx: TCmdProcEx;
    help: AnsiString;
    hidden: Boolean;
    ptr: Pointer; // various data
    msg: AnsiString; // message for var changes
    cheat: Boolean;
    action: Integer; // >= 0 for action commands
    player: Integer; // used for action commands
  end;

  TAlias = record
    name: AnsiString;
    commands: SSArray;
  end;


const
  Step = 32;
  Alpha = 25;
  MsgTime = 144;
  MaxScriptRecursion = 16;

  DEBUG_STRING = 'DEBUG MODE';

var
  ID: DWORD;
  RecursionDepth: Word = 0;
  RecursionLimitHit: Boolean = False;
  Cons_Y: SmallInt;
  Cons_Shown: Boolean; // �������� �� �������?
  Line: AnsiString;
  CPos: Word;
  //ConsoleHistory: SSArray;
  CommandHistory: SSArray;
  Whitelist: SSArray;
  commands: Array of TCommand = nil;
  Aliases: Array of TAlias = nil;
  CmdIndex: Word;
  conSkipLines: Integer = 0;
  MsgArray: Array [0..4] of record
                              Msg: AnsiString;
                              Time: Word;
                            end;

  gInputBinds: Array [0..e_MaxInputKeys - 1] of record
    down, up: SSArray;
  end;
  menu_toggled: BOOLEAN; (* hack for menu controls *)
  gSkipFirstChar: Boolean; (* hack for console/chat input *)


procedure g_Console_Switch;
begin
  gChatShow := False;
  gConsoleShow := not gConsoleShow;
  Cons_Shown := True;
  g_Touch_ShowKeyboard(gConsoleShow or gChatShow);
end;

procedure g_Console_Chat_Switch (Team: Boolean = False);
begin
  if not g_Game_IsNet then Exit;
  gConsoleShow := False;
  gChatShow := not gChatShow;
  gChatTeam := Team;
  Line := '';
  CPos := 1;
  g_Touch_ShowKeyboard(gConsoleShow or gChatShow);
end;

// poor man's floating literal parser; i'm sorry, but `StrToFloat()` sux cocks
function conParseFloat (var res: Single; const s: AnsiString): Boolean;
var
  pos: Integer = 1;
  frac: Single = 1;
  slen: Integer;
begin
  result := false;
  res := 0;
  slen := Length(s);
  while (slen > 0) and (s[slen] <= ' ') do Dec(slen);
  while (pos <= slen) and (s[pos] <= ' ') do Inc(pos);
  if (pos > slen) then exit;
  if (slen-pos = 1) and (s[pos] = '.') then exit; // single dot
  // integral part
  while (pos <= slen) do
  begin
    if (s[pos] < '0') or (s[pos] > '9') then break;
    res := res*10+Byte(s[pos])-48;
    Inc(pos);
  end;
  if (pos <= slen) then
  begin
    // must be a dot
    if (s[pos] <> '.') then exit;
    Inc(pos);
    while (pos <= slen) do
    begin
      if (s[pos] < '0') or (s[pos] > '9') then break;
      frac := frac/10;
      res += frac*(Byte(s[pos])-48);
      Inc(pos);
    end;
  end;
  if (pos <= slen) then exit; // oops
  result := true;
end;


// ////////////////////////////////////////////////////////////////////////// //
// <0: no arg; 0/1: true/false; 666: toggle
function conGetBoolArg (p: SSArray; idx: Integer): Integer;
begin
  if (idx < 0) or (idx > High(p)) then begin result := -1; exit; end;
  result := 0;
  if (p[idx] = '1') or (CompareText(p[idx], 'on') = 0) or (CompareText(p[idx], 'true') = 0) or
     (CompareText(p[idx], 'tan') = 0) or (CompareText(p[idx], 'yes') = 0) then result := 1
  else if (CompareText(p[idx], 'toggle') = 0) or (CompareText(p[idx], 'switch') = 0) or
          (CompareText(p[idx], 't') = 0) then result := 666;
end;


procedure boolVarHandler (me: PCommand; p: SSArray);
  procedure binaryFlag (var flag: Boolean; msg: AnsiString);
  var
    old: Boolean;
  begin
    if (Length(p) > 2) then
    begin
      conwritefln('too many arguments to ''%s''', [p[0]]);
    end
    else
    begin
      old := flag;
      case conGetBoolArg(p, 1) of
        -1: begin end;
         0: if not me.cheat or conIsCheatsEnabled then flag := false else begin conwriteln('not available'); exit; end;
         1: if not me.cheat or conIsCheatsEnabled then flag := true else begin conwriteln('not available'); exit; end;
         666: if not me.cheat or conIsCheatsEnabled then flag := not flag else begin conwriteln('not available'); exit; end;
      end;
      if flag <> old then
        g_Console_WriteGameConfig();
      if (Length(msg) = 0) then msg := p[0] else msg += ':';
      if flag then conwritefln('%s tan', [msg]) else conwritefln('%s ona', [msg]);
    end;
  end;
begin
  binaryFlag(PBoolean(me.ptr)^, me.msg);
end;


procedure intVarHandler (me: PCommand; p: SSArray);
var
  old: Integer;
begin
  if (Length(p) <> 2) then
  begin
    conwritefln('%s %d', [me.cmd, PInteger(me.ptr)^]);
  end
  else
  begin
    try
      old := PInteger(me.ptr)^;
      PInteger(me.ptr)^ := StrToInt(p[1]);
      if PInteger(me.ptr)^ <> old then
        g_Console_WriteGameConfig();
    except
      conwritefln('invalid integer value: "%s"', [p[1]]);
    end;
  end;
end;


procedure conRegVar (const conname: AnsiString; pvar: PBoolean; const ahelp: AnsiString; const amsg: AnsiString; acheat: Boolean=false; ahidden: Boolean=false); overload;
var
  f: Integer;
  cp: PCommand;
begin
  f := Length(commands);
  SetLength(commands, f+1);
  cp := @commands[f];
  cp.cmd := LowerCase(conname);
  cp.proc := nil;
  cp.procEx := boolVarHandler;
  cp.help := ahelp;
  cp.hidden := ahidden;
  cp.ptr := pvar;
  cp.msg := amsg;
  cp.cheat := acheat;
  cp.action := -1;
  cp.player := -1;
end;


procedure conRegVar (const conname: AnsiString; pvar: PInteger; const ahelp: AnsiString; const amsg: AnsiString; acheat: Boolean=false; ahidden: Boolean=false); overload;
var
  f: Integer;
  cp: PCommand;
begin
  f := Length(commands);
  SetLength(commands, f+1);
  cp := @commands[f];
  cp.cmd := LowerCase(conname);
  cp.proc := nil;
  cp.procEx := intVarHandler;
  cp.help := ahelp;
  cp.hidden := ahidden;
  cp.ptr := pvar;
  cp.msg := amsg;
  cp.cheat := acheat;
  cp.action := -1;
  cp.player := -1;
end;


// ////////////////////////////////////////////////////////////////////////// //
type
  PVarSingle = ^TVarSingle;
  TVarSingle = record
    val: PSingle;
    min, max, def: Single; // default will be starting value
  end;


procedure singleVarHandler (me: PCommand; p: SSArray);
var
  pv: PVarSingle;
  nv, old: Single;
  msg: AnsiString;
begin
  if (Length(p) > 2) then
  begin
    conwritefln('too many arguments to ''%s''', [me.cmd]);
    exit;
  end;
  pv := PVarSingle(me.ptr);
  old := pv.val^;
  if (Length(p) = 2) then
  begin
    if me.cheat and (not conIsCheatsEnabled) then begin conwriteln('not available'); exit; end;
    if (CompareText(p[1], 'default') = 0) or (CompareText(p[1], 'def') = 0) or
       (CompareText(p[1], 'd') = 0) or (CompareText(p[1], 'off') = 0) or
       (CompareText(p[1], 'ona') = 0) then
    begin
      pv.val^ := pv.def;
    end
    else
    begin
      if not conParseFloat(nv, p[1]) then
      begin
        conwritefln('%s: ''%s'' doesn''t look like a floating number', [me.cmd, p[1]]);
        exit;
      end;
      if (nv < pv.min) then nv := pv.min;
      if (nv > pv.max) then nv := pv.max;
      pv.val^ := nv;
    end;
  end;
  if pv.val^ <> old then
    g_Console_WriteGameConfig();
  msg := me.msg;
  if (Length(msg) = 0) then msg := me.cmd else msg += ':';
  conwritefln('%s %s', [msg, pv.val^]);
end;


procedure conRegVar (const conname: AnsiString; pvar: PSingle; amin, amax: Single; const ahelp: AnsiString; const amsg: AnsiString; acheat: Boolean=false; ahidden: Boolean=false); overload;
var
  f: Integer;
  cp: PCommand;
  pv: PVarSingle;
begin
  GetMem(pv, sizeof(TVarSingle));
  pv.val := pvar;
  pv.min := amin;
  pv.max := amax;
  pv.def := pvar^;
  f := Length(commands);
  SetLength(commands, f+1);
  cp := @commands[f];
  cp.cmd := LowerCase(conname);
  cp.proc := nil;
  cp.procEx := singleVarHandler;
  cp.help := ahelp;
  cp.hidden := ahidden;
  cp.ptr := pv;
  cp.msg := amsg;
  cp.cheat := acheat;
  cp.action := -1;
  cp.player := -1;
end;


// ////////////////////////////////////////////////////////////////////////// //
function GetStrACmd(var Str: AnsiString): AnsiString;
var
  a: Integer;
begin
  Result := '';
  for a := 1 to Length(Str) do
    if (a = Length(Str)) or (Str[a+1] = ';') then
    begin
      Result := Copy(Str, 1, a);
      Delete(Str, 1, a+1);
      Str := Trim(Str);
      Exit;
    end;
end;

function ParseAlias(Str: AnsiString): SSArray;
begin
  Result := nil;

  Str := Trim(Str);

  if Str = '' then
    Exit;

  while Str <> '' do
  begin
    SetLength(Result, Length(Result)+1);
    Result[High(Result)] := GetStrACmd(Str);
  end;
end;

procedure ConsoleCommands(p: SSArray);
var
  cmd, s: AnsiString;
  a, b: Integer;
  (* F: TextFile; *)
begin
  cmd := LowerCase(p[0]);
  s := '';

  if cmd = 'clear' then
  begin
    //ConsoleHistory := nil;
    cbufClear();
    conSkipLines := 0;

    for a := 0 to High(MsgArray) do
      with MsgArray[a] do
      begin
        Msg := '';
        Time := 0;
      end;
  end;

  if cmd = 'clearhistory' then
    CommandHistory := nil;

  if cmd = 'showhistory' then
    if CommandHistory <> nil then
    begin
      g_Console_Add('');
      for a := 0 to High(CommandHistory) do
        g_Console_Add('  '+CommandHistory[a]);
    end;

  if cmd = 'commands' then
  begin
    g_Console_Add('');
    g_Console_Add('commands list:');
    for a := High(commands) downto 0 do
    begin
      if (Length(commands[a].help) > 0) then
      begin
        g_Console_Add('  '+commands[a].cmd+' -- '+commands[a].help);
      end
      else
      begin
        g_Console_Add('  '+commands[a].cmd);
      end;
    end;
  end;

  if cmd = 'time' then
    g_Console_Add(TimeToStr(Now), True);

  if cmd = 'date' then
    g_Console_Add(DateToStr(Now), True);

  if cmd = 'echo' then
    if Length(p) > 1 then
      begin
        if p[1] = 'ololo' then
          gCheats := True
        else
        begin
          s := '';
          for a := 1 to High(p) do
            s := s + p[a] + ' ';
          g_Console_Add(b_Text_Format(s), True);
        end;
      end
    else
      g_Console_Add('');

  if cmd = 'dump' then
  begin
    (*
    if ConsoleHistory <> nil then
    begin
      if Length(P) > 1 then
        s := P[1]
      else
        s := GameDir+'/console.txt';

      {$I-}
      AssignFile(F, s);
      Rewrite(F);
      if IOResult <> 0 then
      begin
        g_Console_Add(Format(_lc[I_CONSOLE_ERROR_WRITE], [s]));
        CloseFile(F);
        Exit;
      end;

      for a := 0 to High(ConsoleHistory) do
        WriteLn(F, ConsoleHistory[a]);

      CloseFile(F);
      g_Console_Add(Format(_lc[I_CONSOLE_DUMPED], [s]));
      {$I+}
    end;
    *)
  end;

  if cmd = 'exec' then
  begin
    // exec <filename>
    if Length(p) = 2 then
      g_Console_ReadConfig(GameDir + '/' + p[1])
    else
      g_Console_Add('exec <script file>');
  end;

  if cmd = 'writeconfig' then
  begin
    // writeconfig <filename>
    if Length(p) = 2 then
      g_Console_WriteConfig(GameDir + '/' + p[1])
    else
      g_Console_Add('writeconfig <file>');
  end;

  if (cmd = 'ver') or (cmd = 'version') then
  begin
    conwriteln('Doom 2D: Forever v. ' + GAME_VERSION);
    conwritefln('Net protocol v. %d', [NET_PROTOCOL_VER]);
    conwritefln('Build date: %s at %s', [GAME_BUILDDATE, GAME_BUILDTIME]);
  end;

  if cmd = 'alias' then
  begin
    // alias [alias_name] [commands]
    if Length(p) > 1 then
    begin
      for a := 0 to High(Aliases) do
        if Aliases[a].name = p[1] then
        begin
          if Length(p) > 2 then
            Aliases[a].commands := ParseAlias(p[2])
          else
            for b := 0 to High(Aliases[a].commands) do
              g_Console_Add(Aliases[a].commands[b]);
          Exit;
        end;
      SetLength(Aliases, Length(Aliases)+1);
      a := High(Aliases);
      Aliases[a].name := p[1];
      if Length(p) > 2 then
        Aliases[a].commands := ParseAlias(p[2])
      else
        for b := 0 to High(Aliases[a].commands) do
          g_Console_Add(Aliases[a].commands[b]);
    end else
      for a := 0 to High(Aliases) do
        if Aliases[a].commands <> nil then
          g_Console_Add(Aliases[a].name);
  end;

  if cmd = 'call' then
  begin
    // call <alias_name>
    if Length(p) > 1 then
    begin
      if Aliases = nil then
        Exit;
      for a := 0 to High(Aliases) do
        if Aliases[a].name = p[1] then
        begin
          if Aliases[a].commands <> nil then
          begin
            // with this system proper endless loop detection seems either impossible
            // or very dirty to implement, so let's have this instead
            // prevents endless loops
            for b := 0 to High(Aliases[a].commands) do
            begin
              Inc(RecursionDepth);
              RecursionLimitHit := (RecursionDepth > MaxScriptRecursion) or RecursionLimitHit;
              if not RecursionLimitHit then
                g_Console_Process(Aliases[a].commands[b], True);
              Dec(RecursionDepth);
            end;
            if (RecursionDepth = 0) and RecursionLimitHit then
            begin
              g_Console_Add(Format(_lc[I_CONSOLE_ERROR_CALL], [s]));
              RecursionLimitHit := False;
            end;
          end;
          Exit;
        end;
    end
    else
      g_Console_Add('call <alias name>');
  end;
end;

procedure WhitelistCommand(cmd: AnsiString);
var
  a: Integer;
begin
  SetLength(Whitelist, Length(Whitelist)+1);
  a := High(Whitelist);
  Whitelist[a] := LowerCase(cmd);
end;

procedure segfault (p: SSArray);
var
  pp: PByte = nil;
begin
  pp^ := 0;
end;

function GetCommandString (p: SSArray): AnsiString;
  var i: Integer;
begin
  result := '';
  if Length(p) >= 1 then
  begin
    result := p[0];
    for i := 1 to High(p) do
      result := result + '; ' + p[i]
  end
end;

function QuoteStr(str: String): String;
begin
  if Pos(' ', str) > 0 then
    Result := '"' + str + '"'
  else
    Result := str;
end;

procedure BindCommands (p: SSArray);
  var cmd, key: AnsiString; i: Integer;
begin
  cmd := LowerCase(p[0]);
  case cmd of
  'bind':
    // bind <key> [down [up]]
    if (Length(p) >= 2) and (Length(p) <= 4) then
    begin
      i := 0;
      key := LowerCase(p[1]);
      while (i < e_MaxInputKeys) and (key <> LowerCase(e_KeyNames[i])) do inc(i);
      if i < e_MaxInputKeys then
      begin
        if Length(p) = 2 then
          g_Console_Add(QuoteStr(e_KeyNames[i]) + ' = ' + QuoteStr(GetCommandString(gInputBinds[i].down)) + ' ' + QuoteStr(GetCommandString(gInputBinds[i].up)))
        else if Length(p) = 3 then
          g_Console_BindKey(i, p[2], '')
        else (* len = 4 *)
          g_Console_BindKey(i, p[2], p[3])
      end
      else
        g_Console_Add('bind: "' + p[1] + '" is not a key')
    end
    else
    begin
      g_Console_Add('bind <key> <down action> [up action]')
    end;
  'bindlist':
    for i := 0 to e_MaxInputKeys - 1 do
      if (gInputBinds[i].down <> nil) or (gInputBinds[i].up <> nil) then
        g_Console_Add(e_KeyNames[i] + ' ' + QuoteStr(GetCommandString(gInputBinds[i].down)) + ' ' + QuoteStr(GetCommandString(gInputBinds[i].up)));
  'unbind':
    // unbind <key>
    if Length(p) = 2 then
    begin
      key := LowerCase(p[1]);
      i := 0;
      while (i < e_MaxInputKeys) and (key <> LowerCase(e_KeyNames[i])) do inc(i);
      if i < e_MaxInputKeys then
        g_Console_BindKey(i, '')
      else
        g_Console_Add('unbind: "' + p[1] + '" is not a key')
    end
    else
      g_Console_Add('unbind <key>');
  'unbindall':
    for i := 0 to e_MaxInputKeys - 1 do
      g_Console_BindKey(i, '');
  'showkeyboard':
    g_Touch_ShowKeyboard(True);
  'hidekeyboard':
    g_Touch_ShowKeyboard(False);
  'togglemenu':
    if gConsoleShow then
    begin
      g_Console_Switch;
      menu_toggled := True
    end
    else
    begin
      KeyPress(VK_ESCAPE);
      menu_toggled := True
    end;
  'toggleconsole':
    begin
      g_Console_Switch;
      gSkipFirstChar := g_Console_Interactive();
    end;
  'togglechat':
    begin
      if not gConsoleShow and (g_ActiveWindow = nil) then
        g_Console_Chat_Switch;
      gSkipFirstChar := not g_Console_Interactive()
    end;
  'toggleteamchat':
    if gGameSettings.GameMode in [GM_TDM, GM_CTF] then
    begin
      if not gConsoleShow and (g_ActiveWindow = nil) then
        g_Console_Chat_Switch(True);
      gSkipFirstChar := not g_Console_Interactive()
    end;
  end
end;

procedure AddCommand(cmd: AnsiString; proc: TCmdProc; ahelp: AnsiString=''; ahidden: Boolean=false; acheat: Boolean=false);
var
  a: Integer;
  cp: PCommand;
begin
  SetLength(commands, Length(commands)+1);
  a := High(commands);
  cp := @commands[a];
  cp.cmd := LowerCase(cmd);
  cp.proc := proc;
  cp.procEx := nil;
  cp.help := ahelp;
  cp.hidden := ahidden;
  cp.ptr := nil;
  cp.msg := '';
  cp.cheat := acheat;
  cp.action := -1;
  cp.player := -1;
end;

procedure AddAction (cmd: AnsiString; action: Integer; help: AnsiString = ''; hidden: Boolean = False; cheat: Boolean = False);
  const
    PrefixList: array [0..1] of AnsiString = ('+', '-');
    PlayerList: array [0..1] of Integer = (1, 2);
  var
    s: AnsiString;
    i: Integer;

  procedure NewAction (cmd: AnsiString; player: Integer);
    var cp: PCommand;
  begin
    SetLength(commands, Length(commands) + 1);
    cp := @commands[High(commands)];
    cp.cmd := LowerCase(cmd);
    cp.proc := nil;
    cp.procEx := nil;
    cp.help := help;
    cp.hidden := hidden;
    cp.ptr := nil;
    cp.msg := '';
    cp.cheat := cheat;
    cp.action := action;
    cp.player := player;
  end;

begin
  ASSERT(action >= FIRST_ACTION);
  ASSERT(action <= LAST_ACTION);
  for s in PrefixList do
  begin
    NewAction(s + cmd, 0);
    for i in PlayerList do
      NewAction(s + 'p' + IntToStr(i) + '_' + cmd, i - 1)
  end
end;

procedure g_Console_Init();
  var
    a: Integer;
begin
  g_Texture_CreateWAD(ID, GameWAD+':TEXTURES\CONSOLE');
  Cons_Y := -(gScreenHeight div 2);
  gConsoleShow := False;
  gChatShow := False;
  Cons_Shown := False;
  CPos := 1;

  for a := 0 to High(MsgArray) do
    with MsgArray[a] do
    begin
      Msg := '';
      Time := 0;
    end;

  AddCommand('segfault', segfault, 'make segfault');

  AddCommand('bind', BindCommands);
  AddCommand('bindlist', BindCommands);
  AddCommand('unbind', BindCommands);
  AddCommand('unbindall', BindCommands);
  AddCommand('showkeyboard', BindCommands);
  AddCommand('hidekeyboard', BindCommands);
  AddCommand('togglemenu', BindCommands);
  AddCommand('toggleconsole', BindCommands);
  AddCommand('togglechat', BindCommands);
  AddCommand('toggleteamchat', BindCommands);

  AddCommand('clear', ConsoleCommands, 'clear console');
  AddCommand('clearhistory', ConsoleCommands);
  AddCommand('showhistory', ConsoleCommands);
  AddCommand('commands', ConsoleCommands);
  AddCommand('time', ConsoleCommands);
  AddCommand('date', ConsoleCommands);
  AddCommand('echo', ConsoleCommands);
  AddCommand('dump', ConsoleCommands);
  AddCommand('exec', ConsoleCommands);
  AddCommand('writeconfig', ConsoleCommands);
  AddCommand('alias', ConsoleCommands);
  AddCommand('call', ConsoleCommands);
  AddCommand('ver', ConsoleCommands);
  AddCommand('version', ConsoleCommands);

  AddCommand('d_window', DebugCommands);
  AddCommand('d_sounds', DebugCommands);
  AddCommand('d_frames', DebugCommands);
  AddCommand('d_winmsg', DebugCommands);
  AddCommand('d_monoff', DebugCommands);
  AddCommand('d_botoff', DebugCommands);
  AddCommand('d_monster', DebugCommands);
  AddCommand('d_health', DebugCommands);
  AddCommand('d_player', DebugCommands);
  AddCommand('d_joy', DebugCommands);
  AddCommand('d_mem', DebugCommands);

  AddCommand('p1_name', GameCVars);
  AddCommand('p2_name', GameCVars);
  AddCommand('p1_color', GameCVars);
  AddCommand('p2_color', GameCVars);
  AddCommand('r_showscore', GameCVars);
  AddCommand('r_showlives', GameCVars);
  AddCommand('r_showstat', GameCVars);
  AddCommand('r_showkillmsg', GameCVars);
  AddCommand('r_showspect', GameCVars);
  AddCommand('r_showping', GameCVars);
  AddCommand('g_gamemode', GameCVars);
  AddCommand('g_friendlyfire', GameCVars);
  AddCommand('g_weaponstay', GameCVars);
  AddCommand('g_allow_exit', GameCVars);
  AddCommand('g_allow_monsters', GameCVars);
  AddCommand('g_bot_vsmonsters', GameCVars);
  AddCommand('g_bot_vsplayers', GameCVars);
  AddCommand('g_scorelimit', GameCVars);
  AddCommand('g_timelimit', GameCVars);
  AddCommand('g_maxlives', GameCVars);
  AddCommand('g_warmuptime', GameCVars);
  AddCommand('net_interp', GameCVars);
  AddCommand('net_forceplayerupdate', GameCVars);
  AddCommand('net_predictself', GameCVars);
  AddCommand('sv_name', GameCVars);
  AddCommand('sv_passwd', GameCVars);
  AddCommand('sv_maxplrs', GameCVars);
  AddCommand('sv_public', GameCVars);
  AddCommand('sv_intertime', GameCVars);

  AddCommand('quit', GameCommands);
  AddCommand('exit', GameCommands);
  AddCommand('pause', GameCommands);
  AddCommand('endgame', GameCommands);
  AddCommand('restart', GameCommands);
  AddCommand('addbot', GameCommands);
  AddCommand('bot_add', GameCommands);
  AddCommand('bot_addlist', GameCommands);
  AddCommand('bot_addred', GameCommands);
  AddCommand('bot_addblue', GameCommands);
  AddCommand('bot_removeall', GameCommands);
  AddCommand('chat', GameCommands);
  AddCommand('teamchat', GameCommands);
  AddCommand('game', GameCommands);
  AddCommand('host', GameCommands);
  AddCommand('map', GameCommands);
  AddCommand('nextmap', GameCommands);
  AddCommand('endmap', GameCommands);
  AddCommand('goodbye', GameCommands);
  AddCommand('suicide', GameCommands);
  AddCommand('spectate', GameCommands);
  AddCommand('ready', GameCommands);
  AddCommand('kick', GameCommands);
  AddCommand('kick_id', GameCommands);
  AddCommand('ban', GameCommands);
  AddCommand('permban', GameCommands);
  AddCommand('ban_id', GameCommands);
  AddCommand('permban_id', GameCommands);
  AddCommand('unban', GameCommands);
  AddCommand('connect', GameCommands);
  AddCommand('disconnect', GameCommands);
  AddCommand('reconnect', GameCommands);
  AddCommand('say', GameCommands);
  AddCommand('tell', GameCommands);
  AddCommand('overtime', GameCommands);
  AddCommand('rcon_password', GameCommands);
  AddCommand('rcon', GameCommands);
  AddCommand('callvote', GameCommands);
  AddCommand('vote', GameCommands);
  AddCommand('clientlist', GameCommands);
  AddCommand('event', GameCommands);
  AddCommand('screenshot', GameCommands);
  AddCommand('weapon', GameCommands);
  AddCommand('p1_weapon', GameCommands);
  AddCommand('p2_weapon', GameCommands);

  AddCommand('god', GameCheats);
  AddCommand('notarget', GameCheats);
  AddCommand('give', GameCheats); // "exit" too ;-)
  AddCommand('open', GameCheats);
  AddCommand('fly', GameCheats);
  AddCommand('noclip', GameCheats);
  AddCommand('speedy', GameCheats);
  AddCommand('jumpy', GameCheats);
  AddCommand('noreload', GameCheats);
  AddCommand('aimline', GameCheats);
  AddCommand('automap', GameCheats);

  AddAction('jump', ACTION_JUMP);
  AddAction('moveleft', ACTION_MOVELEFT);
  AddAction('moveright', ACTION_MOVERIGHT);
  AddAction('lookup', ACTION_LOOKUP);
  AddAction('lookdown', ACTION_LOOKDOWN);
  AddAction('attack', ACTION_ATTACK);
  AddAction('scores', ACTION_SCORES);
  AddAction('activate', ACTION_ACTIVATE);
  AddAction('strafe', ACTION_STRAFE);
  AddAction('weapnext', ACTION_WEAPNEXT);
  AddAction('weapprev', ACTION_WEAPPREV);

  WhitelistCommand('say');
  WhitelistCommand('tell');
  WhitelistCommand('overtime');
  WhitelistCommand('ready');
  WhitelistCommand('map');
  WhitelistCommand('nextmap');
  WhitelistCommand('endmap');
  WhitelistCommand('restart');
  WhitelistCommand('kick');
  WhitelistCommand('ban');

  WhitelistCommand('addbot');
  WhitelistCommand('bot_add');
  WhitelistCommand('bot_addred');
  WhitelistCommand('bot_addblue');
  WhitelistCommand('bot_removeall');

  WhitelistCommand('g_gamemode');
  WhitelistCommand('g_friendlyfire');
  WhitelistCommand('g_weaponstay');
  WhitelistCommand('g_allow_exit');
  WhitelistCommand('g_allow_monsters');
  WhitelistCommand('g_scorelimit');
  WhitelistCommand('g_timelimit');

  gParsingBinds := True;
  g_Console_ResetBinds;
  g_Console_ReadConfig(GameDir + '/dfconfig.cfg');
  g_Console_ReadConfig(GameDir + '/autoexec.cfg');
  gParsingBinds := False;

  g_Console_Add(Format(_lc[I_CONSOLE_WELCOME], [GAME_VERSION]));
  g_Console_Add('');
end;

procedure g_Console_Update();
var
  a, b: Integer;
begin
  if Cons_Shown then
  begin
  // � �������� ��������:
    if gConsoleShow and (Cons_Y < 0) then
    begin
      Cons_Y := Cons_Y+Step;
    end;

  // � �������� ��������:
    if (not gConsoleShow) and
       (Cons_Y > -(gScreenHeight div 2)) then
      Cons_Y := Cons_Y-Step;

  // ������������ ���������:
    if Cons_Y > 0 then
      Cons_Y := 0;

  // ������������ ���������:
    if Cons_Y <= (-(gScreenHeight div 2)) then
    begin
      Cons_Y := -(gScreenHeight div 2);
      Cons_Shown := False;
    end;
  end;

  a := 0;
  while a <= High(MsgArray) do
  begin
    if MsgArray[a].Time > 0 then
    begin
      if MsgArray[a].Time = 1 then
        begin
          if a < High(MsgArray) then
          begin
            for b := a to High(MsgArray)-1 do
              MsgArray[b] := MsgArray[b+1];

            MsgArray[High(MsgArray)].Time := 0;

            a := a - 1;
          end;
        end
      else
        Dec(MsgArray[a].Time);
    end;

    a := a + 1;
  end;
end;


procedure drawConsoleText ();
var
  CWidth, CHeight: Byte;
  ty: Integer;
  sp, ep: LongWord;
  skip: Integer;

  procedure putLine (sp, ep: LongWord);
  var
    p: LongWord;
    wdt, cw: Integer;
  begin
    p := sp;
    wdt := 0;
    while p <> ep do
    begin
      cw := e_TextureFontCharWidth(cbufAt(p), gStdFont);
      if wdt+cw > gScreenWidth-8 then break;
      //e_TextureFontPrintChar(X, Y: Integer; Ch: Char; FontID: DWORD; Shadow: Boolean = False);
      Inc(wdt, cw);
      cbufNext(p);
    end;
    if p <> ep then putLine(p, ep); // do rest of the line first
    // now print our part
    if skip = 0 then
    begin
      ep := p;
      p := sp;
      wdt := 2;
      while p <> ep do
      begin
        cw := e_TextureFontCharWidth(cbufAt(p), gStdFont);
        e_TextureFontPrintCharEx(wdt, ty, cbufAt(p), gStdFont);
        Inc(wdt, cw);
        cbufNext(p);
      end;
      Dec(ty, CHeight);
    end
    else
    begin
      Dec(skip);
    end;
  end;

begin
  e_TextureFontGetSize(gStdFont, CWidth, CHeight);
  ty := (gScreenHeight div 2)-4-2*CHeight-Abs(Cons_Y);
  skip := conSkipLines;
  cbufLastLine(sp, ep);
  repeat
    putLine(sp, ep);
    if ty+CHeight <= 0 then break;
  until not cbufLineUp(sp, ep);
end;

procedure g_Console_Draw();
var
  CWidth, CHeight: Byte;
  mfW, mfH: Word;
  a, b: Integer;
begin
  e_TextureFontGetSize(gStdFont, CWidth, CHeight);

  for a := 0 to High(MsgArray) do
    if MsgArray[a].Time > 0 then
      e_TextureFontPrintFmt(0, CHeight*a, MsgArray[a].Msg,
        gStdFont, True);

  if not Cons_Shown then
  begin
    if gChatShow then
    begin
      if gChatTeam then
      begin
        e_TextureFontPrintEx(0, gScreenHeight - CHeight - 1, 'say team> ' + Line,
          gStdFont, 255, 255, 255, 1, True);
        e_TextureFontPrintEx((CPos + 9)*CWidth, gScreenHeight - CHeight - 1, '_',
          gStdFont, 255, 255, 255, 1, True);
      end
      else
      begin
        e_TextureFontPrintEx(0, gScreenHeight - CHeight - 1, 'say> ' + Line,
          gStdFont, 255, 255, 255, 1, True);
        e_TextureFontPrintEx((CPos + 4)*CWidth, gScreenHeight - CHeight - 1, '_',
          gStdFont, 255, 255, 255, 1, True);
      end;
    end;
    Exit;
  end;

  if gDebugMode then
  begin
    e_CharFont_GetSize(gMenuFont, DEBUG_STRING, mfW, mfH);
    a := (gScreenWidth - 2*mfW) div 2;
    b := Cons_Y + ((gScreenHeight div 2) - 2*mfH) div 2;
    e_CharFont_PrintEx(gMenuFont, a div 2, b div 2, DEBUG_STRING,
                       _RGB(128, 0, 0), 2.0);
  end;

  e_DrawSize(ID, 0, Cons_Y, Alpha, False, False, gScreenWidth, gScreenHeight div 2);
  e_TextureFontPrint(0, Cons_Y+(gScreenHeight div 2)-CHeight-4, '> '+Line, gStdFont);

  drawConsoleText();
  (*
  if ConsoleHistory <> nil then
  begin
    b := 0;
    if CHeight > 0 then
      if Length(ConsoleHistory) > ((gScreenHeight div 2) div CHeight)-1 then
        b := Length(ConsoleHistory)-((gScreenHeight div 2) div CHeight)+1;

    b := Max(b-Offset, 0);
    d := Max(High(ConsoleHistory)-Offset, 0);

    c := 2;
    for a := d downto b do
    begin
      e_TextureFontPrintFmt(0, (gScreenHeight div 2)-4-c*CHeight-Abs(Cons_Y), ConsoleHistory[a],
                           gStdFont, True);
      c := c + 1;
    end;
  end;
  *)

  e_TextureFontPrint((CPos+1)*CWidth, Cons_Y+(gScreenHeight div 2)-21, '_', gStdFont);
end;

procedure g_Console_Char(C: AnsiChar);
begin
  if not gSkipFirstChar then
  begin
    Insert(C, Line, CPos);
    CPos := CPos + 1;
  end;
  gSkipFirstChar := False
end;


var
  tcomplist: array of AnsiString = nil;
  tcompidx: array of Integer = nil;

procedure Complete ();
var
  i, c: Integer;
  tused: Integer;
  ll, lpfx, cmd: AnsiString;
begin
  if (Length(Line) = 0) then
  begin
    g_Console_Add('');
    for i := 0 to High(commands) do
    begin
      // hidden commands are hidden when cheats aren't enabled
      if commands[i].hidden and not conIsCheatsEnabled then continue;
      if (Length(commands[i].help) > 0) then
      begin
        g_Console_Add('  '+commands[i].cmd+' -- '+commands[i].help);
      end
      else
      begin
        g_Console_Add('  '+commands[i].cmd);
      end;
    end;
    exit;
  end;

  ll := LowerCase(Line);
  lpfx := '';

  if (Length(ll) > 1) and (ll[Length(ll)] = ' ') then
  begin
    ll := Copy(ll, 0, Length(ll)-1);
    for i := 0 to High(commands) do
    begin
      // hidden commands are hidden when cheats aren't enabled
      if commands[i].hidden and not conIsCheatsEnabled then continue;
      if (commands[i].cmd = ll) then
      begin
        if (Length(commands[i].help) > 0) then
        begin
          g_Console_Add('  '+commands[i].cmd+' -- '+commands[i].help);
        end;
      end;
    end;
    exit;
  end;

  // build completion list
  tused := 0;
  for i := 0 to High(commands) do
  begin
    // hidden commands are hidden when cheats aren't enabled
    if commands[i].hidden and not conIsCheatsEnabled then continue;
    cmd := commands[i].cmd;
    if (Length(cmd) >= Length(ll)) and (ll = Copy(cmd, 0, Length(ll))) then
    begin
      if (tused = Length(tcomplist)) then
      begin
        SetLength(tcomplist, Length(tcomplist)+128);
        SetLength(tcompidx, Length(tcompidx)+128);
      end;
      tcomplist[tused] := cmd;
      tcompidx[tused] := i;
      Inc(tused);
      if (Length(cmd) > Length(lpfx)) then lpfx := cmd;
    end;
  end;

  // get longest prefix
  for i := 0 to tused-1 do
  begin
    cmd := tcomplist[i];
    for c := 1 to Length(lpfx) do
    begin
      if (c > Length(cmd)) then break;
      if (cmd[c] <> lpfx[c]) then begin lpfx := Copy(lpfx, 0, c-1); break; end;
    end;
  end;

  if (tused = 0) then exit;

  if (tused = 1) then
  begin
    Line := tcomplist[0]+' ';
    CPos := Length(Line)+1;
  end
  else
  begin
    // has longest prefix?
    if (Length(lpfx) > Length(ll)) then
    begin
      Line := lpfx;
      CPos:= Length(Line)+1;
    end
    else
    begin
      g_Console_Add('');
      for i := 0 to tused-1 do
      begin
        if (Length(commands[tcompidx[i]].help) > 0) then
        begin
          g_Console_Add('  '+tcomplist[i]+' -- '+commands[tcompidx[i]].help);
        end
        else
        begin
          g_Console_Add('  '+tcomplist[i]);
        end;
      end;
    end;
  end;
end;


procedure g_Console_Control(K: Word);
begin
  case K of
    IK_BACKSPACE:
      if (Length(Line) > 0) and (CPos > 1) then
      begin
        Delete(Line, CPos-1, 1);
        CPos := CPos-1;
      end;
    IK_DELETE:
      if (Length(Line) > 0) and (CPos <= Length(Line)) then
        Delete(Line, CPos, 1);
    IK_LEFT, IK_KPLEFT, VK_LEFT, JOY0_LEFT, JOY1_LEFT, JOY2_LEFT, JOY3_LEFT:
      if CPos > 1 then
        CPos := CPos - 1;
    IK_RIGHT, IK_KPRIGHT, VK_RIGHT, JOY0_RIGHT, JOY1_RIGHT, JOY2_RIGHT, JOY3_RIGHT:
      if CPos <= Length(Line) then
        CPos := CPos + 1;
    IK_RETURN, IK_KPRETURN, VK_OPEN, VK_FIRE, JOY0_ATTACK, JOY1_ATTACK, JOY2_ATTACK, JOY3_ATTACK:
    begin
      if Cons_Shown then
        g_Console_Process(Line)
      else
        if gChatShow then
        begin
          if (Length(Line) > 0) and g_Game_IsNet then
          begin
            if gChatTeam then
            begin
              if g_Game_IsClient then
                MC_SEND_Chat(b_Text_Format(Line), NET_CHAT_TEAM)
              else
                MH_SEND_Chat('[' + gPlayer1Settings.name + ']: ' + b_Text_Format(Line),
                  NET_CHAT_TEAM, gPlayer1Settings.Team);
            end
            else
            begin
              if g_Game_IsClient then
                MC_SEND_Chat(b_Text_Format(Line), NET_CHAT_PLAYER)
              else
                MH_SEND_Chat('[' + gPlayer1Settings.name + ']: ' + b_Text_Format(Line),
                NET_CHAT_PLAYER);
            end;
          end;

          Line := '';
          CPos := 1;
          gChatShow := False;
          gJustChatted := True;
          g_Touch_ShowKeyboard(gConsoleShow or gChatShow);
        end;
    end;
    IK_TAB:
      if not gChatShow then
        Complete();
    IK_DOWN, IK_KPDOWN, VK_DOWN, JOY0_DOWN, JOY1_DOWN, JOY2_DOWN, JOY3_DOWN:
      if not gChatShow then
        if (CommandHistory <> nil) and
           (CmdIndex < Length(CommandHistory)) then
        begin
          if CmdIndex < Length(CommandHistory)-1 then
            CmdIndex := CmdIndex + 1;
          Line := CommandHistory[CmdIndex];
          CPos := Length(Line) + 1;
        end;
    IK_UP, IK_KPUP, VK_UP, JOY0_UP, JOY1_UP, JOY2_UP, JOY3_UP:
      if not gChatShow then
        if (CommandHistory <> nil) and
           (CmdIndex <= Length(CommandHistory)) then
        begin
          if CmdIndex > 0 then
            CmdIndex := CmdIndex - 1;
          Line := CommandHistory[CmdIndex];
          Cpos := Length(Line) + 1;
        end;
    IK_PAGEUP, IK_KPPAGEUP, VK_PREV, JOY0_PREV, JOY1_PREV, JOY2_PREV, JOY3_PREV: // PgUp
      if not gChatShow then Inc(conSkipLines);
    IK_PAGEDN, IK_KPPAGEDN, VK_NEXT, JOY0_NEXT, JOY1_NEXT, JOY2_NEXT, JOY3_NEXT: // PgDown
      if not gChatShow and (conSkipLines > 0) then Dec(conSkipLines);
    IK_HOME, IK_KPHOME:
      CPos := 1;
    IK_END, IK_KPEND:
      CPos := Length(Line) + 1;
    IK_A..IK_Z, IK_SPACE, IK_SHIFT, IK_RSHIFT, IK_CAPSLOCK, IK_LBRACKET, IK_RBRACKET,
    IK_SEMICOLON, IK_QUOTE, IK_BACKSLASH, IK_SLASH, IK_COMMA, IK_DOT, IK_EQUALS,
    IK_0, IK_1, IK_2, IK_3, IK_4, IK_5, IK_6, IK_7, IK_8, IK_9, IK_MINUS, IK_EQUALS:
      (* see TEXTINPUT event *)
  else
    if not gSkipFirstChar then
    begin
      if gConsoleShow and g_Console_MatchBind(K, 'toggleconsole') then
        g_Console_Switch;

      if g_Console_MatchBind(K, 'togglemenu') then
      begin
        menu_toggled := True;
        if gChatShow then
          g_Console_Chat_Switch
        else if gConsoleShow then
          g_Console_Switch
      end
    end
  end
end;

function GetStr(var Str: AnsiString): AnsiString;
var
  a, b: Integer;
begin
  Result := '';
  if Str[1] = '"' then
  begin
    for b := 1 to Length(Str) do
      if (b = Length(Str)) or (Str[b+1] = '"') then
      begin
        Result := Copy(Str, 2, b-1);
        Delete(Str, 1, b+1);
        Str := Trim(Str);
        Exit;
      end;
  end;

  for a := 1 to Length(Str) do
    if (a = Length(Str)) or (Str[a+1] = ' ') then
    begin
      Result := Copy(Str, 1, a);
      Delete(Str, 1, a+1);
      Str := Trim(Str);
      Exit;
    end;
end;

function ParseString(Str: AnsiString): SSArray;
begin
  Result := nil;

  Str := Trim(Str);

  if Str = '' then
    Exit;

  while Str <> '' do
  begin
    SetLength(Result, Length(Result)+1);
    Result[High(Result)] := GetStr(Str);
  end;
end;

procedure g_Console_Add (L: AnsiString; show: Boolean=false);

  procedure conmsg (s: AnsiString);
  var
    a: Integer;
  begin
    if length(s) = 0 then exit;
    for a := 0 to High(MsgArray) do
    begin
      with MsgArray[a] do
      begin
        if Time = 0 then
        begin
          Msg := s;
          Time := MsgTime;
          exit;
        end;
      end;
    end;
    for a := 0 to High(MsgArray)-1 do MsgArray[a] := MsgArray[a+1];
    with MsgArray[High(MsgArray)] do
    begin
      Msg := L;
      Time := MsgTime;
    end;
  end;

var
  f: Integer;
begin
  // put it to console
  cbufPut(L);
  if (length(L) = 0) or ((L[length(L)] <> #10) and (L[length(L)] <> #13)) then cbufPut(#10);

  // now show 'em out of console too
  show := show and gAllowConsoleMessages;
  if show and gShowMessages then
  begin
    // ����� ����� � ���������� �� �������
    while length(L) > 0 do
    begin
      f := Pos(#10, L);
      if f <= 0 then f := length(L)+1;
      conmsg(Copy(L, 1, f-1));
      Delete(L, 1, f);
    end;
  end;

  //SetLength(ConsoleHistory, Length(ConsoleHistory)+1);
  //ConsoleHistory[High(ConsoleHistory)] := L;

  (*
{$IFDEF HEADLESS}
  e_WriteLog('CON: ' + L, MSG_NOTIFY);
{$ENDIF}
  *)
end;


var
  consolewriterLastWasEOL: Boolean = false;

procedure consolewriter (constref buf; len: SizeUInt);
var
  b: PByte;
begin
  if (len < 1) then exit;
  b := PByte(@buf);
  consolewriterLastWasEOL := (b[len-1] = 13) or (b[len-1] = 10);
  while (len > 0) do
  begin
    if (b[0] <> 13) and (b[0] <> 10) then
    begin
      cbufPut(AnsiChar(b[0]));
    end
    else
    begin
      if (len > 1) and (b[0] = 13) then begin len -= 1; b += 1; end;
      cbufPut(#10);
    end;
    len -= 1;
    b += 1;
  end;
end;


// returns formatted string if `writerCB` is `nil`, empty string otherwise
//function formatstrf (const fmt: AnsiString; args: array of const; writerCB: TFormatStrFCallback=nil): AnsiString;
//TFormatStrFCallback = procedure (constref buf; len: SizeUInt);
procedure conwriteln (const s: AnsiString; show: Boolean=false);
begin
  g_Console_Add(s, show);
end;


procedure conwritefln (const s: AnsiString; args: array of const; show: Boolean=false);
begin
  if show then
  begin
    g_Console_Add(formatstrf(s, args), true);
  end
  else
  begin
    consolewriterLastWasEOL := false;
    formatstrf(s, args, consolewriter);
    if not consolewriterLastWasEOL then cbufPut(#10);
  end;
end;


procedure g_Console_Clear();
begin
  //ConsoleHistory := nil;
  cbufClear();
  conSkipLines := 0;
end;

procedure AddToHistory(L: AnsiString);
var
  len: Integer;
begin
  len := Length(CommandHistory);

  if (len = 0) or
     (LowerCase(CommandHistory[len-1]) <> LowerCase(L)) then
  begin
    SetLength(CommandHistory, len+1);
    CommandHistory[len] := L;
  end;

  CmdIndex := Length(CommandHistory);
end;

function g_Console_CommandBlacklisted(C: AnsiString): Boolean;
var
  Arr: SSArray;
  i: Integer;
begin
  Result := True;

  Arr := nil;

  if Trim(C) = '' then
    Exit;

  Arr := ParseString(C);
  if Arr = nil then
    Exit;

  for i := 0 to High(Whitelist) do
    if Whitelist[i] = LowerCase(Arr[0]) then
      Result := False;
end;

procedure g_Console_Process(L: AnsiString; quiet: Boolean = False);
var
  Arr: SSArray;
  i: Integer;
begin
  Arr := nil;

  if Trim(L) = '' then
    Exit;

  conSkipLines := 0; // "unscroll"

  if L = 'goobers' then
  begin
    Line := '';
    CPos := 1;
    gCheats := true;
    g_Console_Add('Your memory serves you well.');
    exit;
  end;

  if not quiet then
  begin
    g_Console_Add('> '+L);
    Line := '';
    CPos := 1;
  end;

  Arr := ParseString(L);
  if Arr = nil then
    Exit;

  if commands = nil then
    Exit;

  if not quiet then
    AddToHistory(L);

  for i := 0 to High(commands) do
  begin
    if commands[i].cmd = LowerCase(Arr[0]) then
    begin
      if commands[i].action >= 0 then
      begin
        gPlayerAction[commands[i].player, commands[i].action] := commands[i].cmd[1] = '+';
        exit
      end;
      if assigned(commands[i].procEx) then
      begin
        commands[i].procEx(@commands[i], Arr);
        exit
      end;
      if assigned(commands[i].proc) then
      begin
        commands[i].proc(Arr);
        exit
      end
    end
  end;

  g_Console_Add(Format(_lc[I_CONSOLE_UNKNOWN], [Arr[0]]));
end;


function g_Console_Interactive: Boolean;
begin
  Result := gConsoleShow
end;

procedure g_Console_BindKey (key: Integer; down: AnsiString; up: AnsiString = '');
begin
  //e_LogWritefln('bind "%s" "%s" <%s>', [LowerCase(e_KeyNames[key]), cmd, key]);
  ASSERT(key >= 0);
  ASSERT(key < e_MaxInputKeys);
  if key > 0 then
  begin
    gInputBinds[key].down := ParseAlias(down);
    gInputBinds[key].up := ParseAlias(up);
  end;
  g_Console_WriteGameConfig();
end;

function g_Console_MatchBind (key: Integer; down: AnsiString; up: AnsiString = ''): Boolean;

  function EqualsCommandLists (a, b: SSArray): Boolean;
    var i, len: Integer;
  begin
    result := False;
    len := Length(a);
    if len = Length(b) then
    begin
      i := 0;
      while (i < len) and (a[i] = b[i]) do inc(i);
      if i >= len then
        result := True
    end
  end;

begin
  ASSERT(key >= 0);
  ASSERT(key < e_MaxInputKeys);
  result := EqualsCommandLists(ParseAlias(down), gInputBinds[key].down) and EqualsCommandLists(ParseAlias(up), gInputBinds[key].up)
end;

function g_Console_FindBind (n: Integer; down: AnsiString; up: AnsiString = ''): Integer;
  var i: Integer;
begin
  ASSERT(n >= 1);
  result := 0;
  if commands = nil then Exit;
  i := 0;
  while (n >= 1) and (i < e_MaxInputKeys) do
  begin
    if g_Console_MatchBind(i, down, up) then
    begin
      result := i;
      dec(n)
    end;
    inc(i)
  end;
  if n >= 1 then
    result := 0
end;

function g_Console_Action (action: Integer): Boolean;
  var i, len: Integer;
begin
  ASSERT(action >= FIRST_ACTION);
  ASSERT(action <= LAST_ACTION);
  i := 0;
  len := Length(gPlayerAction);
  while (i < len) and (not gPlayerAction[i, action]) do inc(i);
  Result := i < len
end;

procedure g_Console_ProcessBind (key: Integer; down: Boolean);
  var i: Integer;
begin
  if (not g_GUIGrabInput) and (key >= 0) and (key < e_MaxInputKeys) and ((gInputBinds[key].down <> nil) or (gInputBinds[key].up <> nil)) then
  begin
    if down then
    begin
      if not gChatShow then
        for i := 0 to High(gInputBinds[key].down) do
          g_Console_Process(gInputBinds[key].down[i], True);
    end
    else
      for i := 0 to High(gInputBinds[key].up) do
        g_Console_Process(gInputBinds[key].up[i], True)
  end;
  if down and not menu_toggled then
    KeyPress(key);
  menu_toggled := False
end;

procedure g_Console_ResetBinds;
  var i: Integer;
begin
  for i := 0 to e_MaxInputKeys - 1 do
    g_Console_BindKey(i, '', '');

  g_Console_BindKey(IK_GRAVE, 'toggleconsole');
  g_Console_BindKey(IK_ESCAPE, 'togglemenu');
  g_Console_BindKey(IK_A, '+p1_moveleft', '-p1_moveleft');
  g_Console_BindKey(IK_D, '+p1_moveright', '-p1_moveright');
  g_Console_BindKey(IK_W, '+p1_lookup', '-p1_lookup');
  g_Console_BindKey(IK_S, '+p1_lookdown', '-p1_lookdown');
  g_Console_BindKey(IK_SPACE, '+p1_jump', '-p1_jump');
  g_Console_BindKey(IK_H, '+p1_attack', '-p1_attack');
  g_Console_BindKey(IK_J, '+p1_activate', '-p1_activate');
  g_Console_BindKey(IK_E, '+p1_weapnext', '-p1_weapnext');
  g_Console_BindKey(IK_Q, '+p1_weapprev', '-p1_weapprev');
  g_Console_BindKey(IK_ALT, '+p1_strafe', '-p1_strafe');
  g_Console_BindKey(IK_1, 'p1_weapon 1');
  g_Console_BindKey(IK_2, 'p1_weapon 2');
  g_Console_BindKey(IK_3, 'p1_weapon 3');
  g_Console_BindKey(IK_4, 'p1_weapon 4');
  g_Console_BindKey(IK_5, 'p1_weapon 5');
  g_Console_BindKey(IK_6, 'p1_weapon 6');
  g_Console_BindKey(IK_7, 'p1_weapon 7');
  g_Console_BindKey(IK_8, 'p1_weapon 8');
  g_Console_BindKey(IK_9, 'p1_weapon 9');
  g_Console_BindKey(IK_0, 'p1_weapon 10');
  g_Console_BindKey(IK_MINUS, 'p1_weapon 11');
  g_Console_BindKey(IK_T, 'togglechat');
  g_Console_BindKey(IK_Y, 'toggleteamchat');
  g_Console_BindKey(IK_F11, 'screenshot');
  g_Console_BindKey(IK_TAB, '+p1_scores', '-p1_scores');
  g_Console_BindKey(IK_PAUSE, 'pause');
  g_Console_BindKey(IK_F1, 'vote');

  (* for i := 0 to e_MaxJoys - 1 do *)
  for i := 0 to 1 do
  begin
    g_Console_BindKey(e_JoyHatToKey(i, 0, HAT_LEFT), '+p' + IntToStr(i mod 2 + 1) + '_moveleft', '-p' + IntToStr(i mod 2 + 1) + '_moveleft');
    g_Console_BindKey(e_JoyHatToKey(i, 0, HAT_RIGHT), '+p' + IntToStr(i mod 2 + 1) + '_moveright', '-p' + IntToStr(i mod 2 + 1) + '_moveright');
    g_Console_BindKey(e_JoyHatToKey(i, 0, HAT_UP), '+p' + IntToStr(i mod 2 + 1) + '_lookup', '-p' + IntToStr(i mod 2 + 1) + '_lookup');
    g_Console_BindKey(e_JoyHatToKey(i, 0, HAT_DOWN), '+p' + IntToStr(i mod 2 + 1) + '_lookdown', '-p' + IntToStr(i mod 2 + 1) + '_lookdown');
    g_Console_BindKey(e_JoyButtonToKey(i, 2), '+p' + IntToStr(i mod 2 + 1) + '_jump', '-p' + IntToStr(i mod 2 + 1) + '_jump');
    g_Console_BindKey(e_JoyButtonToKey(i, 0), '+p' + IntToStr(i mod 2 + 1) + '_attack', '-p' + IntToStr(i mod 2 + 1) + '_attack');
    g_Console_BindKey(e_JoyButtonToKey(i, 3), '+p' + IntToStr(i mod 2 + 1) + '_activate', '-p' + IntToStr(i mod 2 + 1) + '_activate');
    g_Console_BindKey(e_JoyButtonToKey(i, 1), '+p' + IntToStr(i mod 2 + 1) + '_weapnext', '-p' + IntToStr(i mod 2 + 1) + '_weapnext');
    g_Console_BindKey(e_JoyButtonToKey(i, 4), '+p' + IntToStr(i mod 2 + 1) + '_weapprev', '-p' + IntToStr(i mod 2 + 1) + '_weapprev');
    g_Console_BindKey(e_JoyButtonToKey(i, 7), '+p' + IntToStr(i mod 2 + 1) + '_strafe', '-p' + IntToStr(i mod 2 + 1) + '_strafe');
    g_Console_BindKey(e_JoyButtonToKey(i, 10), 'togglemenu');
  end;

  g_Console_BindKey(VK_ESCAPE, 'togglemenu');
  g_Console_BindKey(VK_LSTRAFE, '+moveleft; +strafe', '-moveleft; -strafe');
  g_Console_BindKey(VK_RSTRAFE, '+moveright; +strafe', '-moveright; -strafe');
  g_Console_BindKey(VK_LEFT, '+moveleft', '-moveleft');
  g_Console_BindKey(VK_RIGHT, '+moveright', '-moveright');
  g_Console_BindKey(VK_UP, '+lookup', '-lookup');
  g_Console_BindKey(VK_DOWN, '+lookdown', '-lookdown');
  g_Console_BindKey(VK_JUMP, '+jump', '-jump');
  g_Console_BindKey(VK_FIRE, '+attack', '-attack');
  g_Console_BindKey(VK_OPEN, '+activate', '-activate');
  g_Console_BindKey(VK_NEXT, '+weapnext', '-weapnext');
  g_Console_BindKey(VK_PREV, '+weapprev', '-weapprev');
  g_Console_BindKey(VK_STRAFE, '+strafe', '-strafe');
  g_Console_BindKey(VK_0, 'weapon 1');
  g_Console_BindKey(VK_1, 'weapon 2');
  g_Console_BindKey(VK_2, 'weapon 3');
  g_Console_BindKey(VK_3, 'weapon 4');
  g_Console_BindKey(VK_4, 'weapon 5');
  g_Console_BindKey(VK_5, 'weapon 6');
  g_Console_BindKey(VK_6, 'weapon 7');
  g_Console_BindKey(VK_7, 'weapon 8');
  g_Console_BindKey(VK_8, 'weapon 9');
  g_Console_BindKey(VK_9, 'weapon 10');
  g_Console_BindKey(VK_A, 'weapon 11');
  g_Console_BindKey(VK_CHAT, 'togglechat');
  g_Console_BindKey(VK_TEAM, 'toggleteamchat');
  g_Console_BindKey(VK_CONSOLE, 'toggleconsole');
  g_Console_BindKey(VK_PRINTSCR, 'screenshot');
  g_Console_BindKey(VK_STATUS, '+scores', '-scores');
  g_Console_BindKey(VK_SHOWKBD, 'showkeyboard');
  g_Console_BindKey(VK_HIDEKBD, 'hidekeyboard');
end;

procedure g_Console_ReadConfig (filename: String);
  var f: TextFile; s: AnsiString; i, len: Integer;
begin
  if FileExists(filename) then
  begin
    AssignFile(f, filename);
    Reset(f);
    while not EOF(f) do
    begin
      ReadLn(f, s);
      len := Length(s);
      if len > 0 then
      begin
        i := 1;
        (* skip spaces *)
        while (i <= len) and (s[i] <= ' ') do inc(i);
        (* skip comments *)
        if (i <= len) and ((s[i] <> '#') and ((i + 1 > len) or (s[i] <> '/') or (s[i + 1] <> '/'))) then
          g_Console_Process(s, True);
      end
    end;
    CloseFile(f);
  end
end;

procedure g_Console_WriteConfig (filename: String);
  var f: TextFile; i, j: Integer;
begin
  AssignFile(f, filename);
  Rewrite(f);
  WriteLn(f, '// generated by doom2d, do not modify');
  WriteLn(f, 'unbindall');
  for i := 0 to e_MaxInputKeys - 1 do
    if (Length(gInputBinds[i].down) > 0) or (Length(gInputBinds[i].up) > 0) then
    begin
      Write(f, 'bind ', e_KeyNames[i], ' ', QuoteStr(GetCommandString(gInputBinds[i].down)));
      if Length(gInputBinds[i].down) = 0 then
        Write(f, '""');
      if Length(gInputBinds[i].up) > 0 then
        Write(f, ' ', QuoteStr(GetCommandString(gInputBinds[i].up)));
      WriteLn(f, '');
    end;
  for i := 0 to High(commands) do
  begin
    if not commands[i].cheat then
    begin
      if @commands[i].procEx = @boolVarHandler then
      begin
        if PBoolean(commands[i].ptr)^ then j := 1 else j := 0;
        WriteLn(f, commands[i].cmd, ' ', j)
      end
      else if @commands[i].procEx = @intVarHandler then
      begin
        WriteLn(f, commands[i].cmd, ' ', PInteger(commands[i].ptr)^)
      end
      else if @commands[i].procEx = @singleVarHandler then
      begin
        WriteLn(f, commands[i].cmd, ' ', PVarSingle(commands[i].ptr).val^:0:6)
      end
    end
  end;
  CloseFile(f)
end;

procedure g_Console_WriteGameConfig;
begin
  if gParsingBinds then
    Exit;
  g_Console_WriteConfig(GameDir + '/dfconfig.cfg');
end;

end.
