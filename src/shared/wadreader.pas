{$MODE DELPHI}
unit wadreader;

{$DEFINE SFS_DWFAD_DEBUG}

interface

uses
  sfs, xstreams;


type
  SArray = array of ShortString;

  TWADFile = class(TObject)
  private
    fFileName: AnsiString; // empty: not opened
    fIter: TSFSFileList;

    function getIsOpen (): Boolean;

   public
    constructor Create();
    destructor Destroy(); override;

    procedure FreeWAD();

    function ReadFile (FileName: AnsiString): Boolean;
    function ReadMemory (Data: Pointer; Len: LongWord): Boolean;

    function GetResource (name: AnsiString; var pData: Pointer; var Len: Integer): Boolean;
    function GetRootResources (): SArray;

    property isOpen: Boolean read getIsOpen;
  end;


function g_ExtractWadName (resourceStr: AnsiString): AnsiString;
function g_ExtractWadNameNoPath (resourceStr: AnsiString): AnsiString;
function g_ExtractFilePath (resourceStr: AnsiString): AnsiString;
function g_ExtractFileName (resourceStr: AnsiString): AnsiString; // without path
function g_ExtractFilePathName (resourceStr: AnsiString): AnsiString;

// return fixed AnsiString or empty AnsiString
function findDiskWad (fname: AnsiString): AnsiString;


implementation

uses
  SysUtils, Classes, BinEditor, e_log, g_options, utils;


function findDiskWad (fname: AnsiString): AnsiString;
begin
  result := '';
  if not findFileCI(fname) then
  begin
    //e_WriteLog(Format('findDiskWad: error looking for [%s]', [fname]), MSG_NOTIFY);
    if StrEquCI1251(ExtractFileExt(fname), '.wad') then
    begin
      fname := ChangeFileExt(fname, '.pk3');
      //e_WriteLog(Format('  looking for [%s]', [fname]), MSG_NOTIFY);
      if not findFileCI(fname) then
      begin
        fname := ChangeFileExt(fname, '.zip');
        //e_WriteLog(Format('  looking for [%s]', [fname]), MSG_NOTIFY);
        if not findFileCI(fname) then exit;
      end;
    end
    else
    begin
      exit;
    end;
  end;
  //e_WriteLog(Format('findDiskWad: FOUND [%s]', [fname]), MSG_NOTIFY);
  result := fname;
end;


function normSlashes (s: AnsiString): AnsiString;
var
  f: Integer;
begin
  for f := 1 to length(s) do if s[f] = '\' then s[f] := '/';
  result := s;
end;

function g_ExtractWadNameNoPath (resourceStr: AnsiString): AnsiString;
var
  f, c: Integer;
begin
  for f := length(resourceStr) downto 1 do
  begin
    if resourceStr[f] = ':' then
    begin
      result := normSlashes(Copy(resourceStr, 1, f-1));
      c := length(result);
      while (c > 0) and (result[c] <> '/') do Dec(c);
      if c > 0 then result := Copy(result, c+1, length(result));
      exit;
    end;
  end;
  result := '';
end;

function g_ExtractWadName (resourceStr: AnsiString): AnsiString;
var
  f: Integer;
begin
  for f := length(resourceStr) downto 1 do
  begin
    if resourceStr[f] = ':' then
    begin
      result := normSlashes(Copy(resourceStr, 1, f-1));
      exit;
    end;
  end;
  result := '';
end;

function g_ExtractFilePath (resourceStr: AnsiString): AnsiString;
var
  f, lastSlash: Integer;
begin
  result := '';
  lastSlash := -1;
  for f := length(resourceStr) downto 1 do
  begin
    if (lastSlash < 0) and (resourceStr[f] = '\') or (resourceStr[f] = '/') then lastSlash := f;
    if resourceStr[f] = ':' then
    begin
      if lastSlash > 0 then result := normSlashes(Copy(resourceStr, f, lastSlash-f));
      exit;
    end;
  end;
  if lastSlash > 0 then result := normSlashes(Copy(resourceStr, 1, lastSlash-1));
end;

function g_ExtractFileName (resourceStr: AnsiString): AnsiString; // without path
var
  f, lastSlash: Integer;
begin
  result := '';
  lastSlash := -1;
  for f := length(resourceStr) downto 1 do
  begin
    if (lastSlash < 0) and (resourceStr[f] = '\') or (resourceStr[f] = '/') then lastSlash := f;
    if resourceStr[f] = ':' then
    begin
      if lastSlash > 0 then result := Copy(resourceStr, lastSlash+1, length(resourceStr));
      exit;
    end;
  end;
  if lastSlash > 0 then result := Copy(resourceStr, lastSlash+1, length(resourceStr));
end;

function g_ExtractFilePathName (resourceStr: AnsiString): AnsiString;
var
  f: Integer;
begin
  result := '';
  for f := length(resourceStr) downto 1 do
  begin
    if resourceStr[f] = ':' then
    begin
      result := normSlashes(Copy(resourceStr, f+1, length(resourceStr)));
      exit;
    end;
  end;
end;



{ TWADFile }
constructor TWADFile.Create();
begin
  fFileName := '';
end;


destructor TWADFile.Destroy();
begin
  FreeWAD();
  inherited;
end;


function TWADFile.getIsOpen (): Boolean;
begin
  result := (fFileName <> '');
end;


procedure TWADFile.FreeWAD();
begin
  if fIter <> nil then FreeAndNil(fIter);
  //if fFileName <> '' then e_WriteLog(Format('TWADFile.ReadFile: [%s] closed', [fFileName]), MSG_NOTIFY);
  fFileName := '';
end;


function removeExt (s: AnsiString): AnsiString;
var
  i: Integer;
begin
  i := length(s)+1;
  while (i > 1) and (s[i-1] <> '.') and (s[i-1] <> '/') do Dec(i);
  if (i > 1) and (s[i-1] = '.') then
  begin
    //writeln('[', s, '] -> [', Copy(s, 1, i-2), ']');
    s := Copy(s, 1, i-2);
  end;
  result := s;
end;

function TWADFile.GetResource (name: AnsiString; var pData: Pointer; var Len: Integer): Boolean;
var
  f, lastSlash: Integer;
  fi: TSFSFileInfo;
  fs: TStream;
  fpp: Pointer;
  rpath, rname: AnsiString;
  //fn: AnsiString;
begin
  Result := False;
  if not isOpen or (fIter = nil) then Exit;
  rname := removeExt(name);
  if length(rname) = 0 then Exit; // just in case
  lastSlash := -1;
  for f := 1 to length(rname) do
  begin
    if rname[f] = '\' then rname[f] := '/';
    if rname[f] = '/' then lastSlash := f;
  end;
  if lastSlash > 0 then
  begin
    rpath := Copy(rname, 1, lastSlash);
    Delete(rname, 1, lastSlash);
  end
  else
  begin
    rpath := '';
  end;
  // backwards, due to possible similar names and such
  for f := fIter.Count-1 downto 0 do
  begin
    fi := fIter.Files[f];
    if fi = nil then continue;
    //e_WriteLog(Format('DFWAD: searching for [%s : %s] in [%s]; current is [%s : %s]', [Section, Resource, fFileName, fi.path, fi.name]), MSG_NOTIFY);
    if StrEquCI1251(fi.path, rpath) and StrEquCI1251(removeExt(fi.name), rname) then
    begin
      // i found her!
      //fn := fFileName+'::'+fi.path+fi.name;
      //fs := SFSFileOpen(fn);
      try
        fs := fIter.volume.OpenFileByIndex(f);
      except
        fs := nil;
      end;
      if fs = nil then
      begin
        e_WriteLog(Format('DFWAD: can''t open file [%s] in [%s]', [name, fFileName]), MSG_WARNING);
        break;
      end;
      Len := Integer(fs.size);
      GetMem(pData, Len);
      fpp := pData;
      try
        fs.ReadBuffer(pData^, Len);
        fpp := nil;
      finally
        if fpp <> nil then
        begin
          FreeMem(fpp);
          pData := nil;
          Len := 0;
        end;
        fs.Free;
      end;
      result := true;
      {$IFDEF SFS_DWFAD_DEBUG}
      if gSFSDebug then
        e_WriteLog(Format('DFWAD: file [%s] FOUND in [%s]; size is %d bytes', [name, fFileName, Len]), MSG_NOTIFY);
      {$ENDIF}
      exit;
    end;
  end;
  e_WriteLog(Format('DFWAD: file [%s] not found in [%s]', [name, fFileName]), MSG_WARNING);
end;


function TWADFile.GetRootResources (): SArray;
var
  f: Integer;
  fi: TSFSFileInfo;
begin
  Result := nil;
  if not isOpen or (fIter = nil) then Exit;
  for f := 0 to fIter.Count-1 do
  begin
    fi := fIter.Files[f];
    if fi = nil then continue;
    if length(fi.name) = 0 then continue;
    if length(fi.path) = 0 then
    begin
      SetLength(result, Length(result)+1);
      result[high(result)] := removeExt(fi.name);
    end;
  end;
end;


function TWADFile.ReadFile (FileName: AnsiString): Boolean;
var
  rfn: AnsiString;
  //f: Integer;
  //fi: TSFSFileInfo;
begin
  Result := False;
  //e_WriteLog(Format('TWADFile.ReadFile: [%s]', [FileName]), MSG_NOTIFY);
  FreeWAD();
  rfn := findDiskWad(FileName);
  if length(rfn) = 0 then
  begin
    e_WriteLog(Format('TWADFile.ReadFile: error looking for [%s]', [FileName]), MSG_NOTIFY);
    exit;
  end;
  {$IFDEF SFS_DWFAD_DEBUG}
  if gSFSDebug then e_WriteLog(Format('TWADFile.ReadFile: FOUND [%s]', [rfn]), MSG_NOTIFY);
  {$ENDIF}
  // cache this wad
  try
    if gSFSFastMode then
    begin
      if not SFSAddDataFile(rfn, true) then exit;
    end
    else
    begin
      if not SFSAddDataFileTemp(rfn, true) then exit;
    end;
  except
    exit;
  end;
  fIter := SFSFileList(rfn);
  if fIter = nil then Exit;
  fFileName := rfn;
  {$IFDEF SFS_DWFAD_DEBUG}
  if gSFSDebug then e_WriteLog(Format('TWADFile.ReadFile: [%s] opened', [fFileName]), MSG_NOTIFY);
  {$ENDIF}
  Result := True;
end;


var
  uniqueCounter: Integer = 0;

function TWADFile.ReadMemory (Data: Pointer; Len: LongWord): Boolean;
var
  fn: AnsiString;
  st: TStream = nil;
  //f: Integer;
  //fi: TSFSFileInfo;
begin
  Result := False;
  FreeWAD();
  if (Data = nil) or (Len = 0) then
  begin
    e_WriteLog('TWADFile.ReadMemory: EMPTY SUBWAD!', MSG_WARNING);
    Exit;
  end;

  fn := Format(' -- memwad %d -- ', [uniqueCounter]);
  Inc(uniqueCounter);
  {$IFDEF SFS_DWFAD_DEBUG}
    e_WriteLog(Format('TWADFile.ReadMemory: [%s]', [fn]), MSG_NOTIFY);
  {$ENDIF}

  try
    st := TSFSMemoryStreamRO.Create(Data, Len);
    if not SFSAddSubDataFile(fn, st, true) then
    begin
      st.Free;
      Exit;
    end;
  except
    st.Free;
    Exit;
  end;

  fIter := SFSFileList(fn);
  if fIter = nil then Exit;

  fFileName := fn;
  {$IFDEF SFS_DWFAD_DEBUG}
    e_WriteLog(Format('TWADFile.ReadMemory: [%s] opened', [fFileName]), MSG_NOTIFY);
  {$ENDIF}

  {
  for f := 0 to fIter.Count-1 do
  begin
    fi := fIter.Files[f];
    if fi = nil then continue;
    st := fIter.volume.OpenFileByIndex(f);
    if st = nil then
    begin
      e_WriteLog(Format('[%s]: [%s : %s] CAN''T OPEN', [fFileName, fi.path, fi.name]), MSG_NOTIFY);
    end
    else
    begin
      e_WriteLog(Format('[%s]: [%s : %s] %u', [fFileName, fi.path, fi.name, st.size]), MSG_NOTIFY);
      st.Free;
    end;
  end;
  //fIter.volume.OpenFileByIndex(0);
  }

  Result := True;
end;


begin
  sfsDiskDirs := '<exedir>/data'; //FIXME
end.