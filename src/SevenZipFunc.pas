unit SevenZipFunc;

{$IFDEF FPC}
{$MODE DELPHI}
{$ENDIF}

interface

uses
  WcxPlugin;

{ Mandatory }
function OpenArchiveW(var ArchiveData : tOpenArchiveDataW) : TArcHandle;stdcall;
function ReadHeaderExW(hArcData : TArcHandle; var HeaderData: THeaderDataExW) : Integer;stdcall;
function ProcessFileW(hArcData : TArcHandle; Operation : Integer; DestPath, DestName : PWideChar) : Integer;stdcall;
function CloseArchive (hArcData : TArcHandle) : Integer;stdcall;
procedure SetChangeVolProcW(hArcData : TArcHandle; pChangeVolProc : TChangeVolProcW);stdcall;
procedure SetProcessDataProcW(hArcData : TArcHandle; pProcessDataProc : TProcessDataProcW);stdcall;
{ Optional }
function PackFilesW(PackedFile: PWideChar; SubPath: PWideChar; SrcPath: PWideChar; AddList: PWideChar; Flags: Integer): Integer; stdcall;
function DeleteFilesW(PackedFile, DeleteList: PWideChar): Integer; stdcall;
function CanYouHandleThisFileW(FileName: PWideChar): Boolean; stdcall;
procedure PackSetDefaultParams(dps: PPackDefaultParamStruct); stdcall;

implementation

uses
  JwaWinBase, Windows, SysUtils, Classes, JclCompression, SevenZip, SevenZipAdv,
  SevenZipDlg, SevenZipLng, LazFileUtils;

type

   { ESevenZipAbort }

    ESevenZipAbort = class(EJclCompressionError)

    end;

  { TSevenZipUpdate }

  TSevenZipUpdate = class
    procedure JclCompressionPassword(Sender: TObject; var Password: WideString);
    procedure JclCompressionProgress(Sender: TObject; const Value, MaxValue: Int64); virtual;
  end;

  { TSevenZipHandle }

  TSevenZipHandle = class(TSevenZipUpdate)
    Index,
    Count: LongWord;
    FileName: UTF8String;
    Directory: UTF8String;
    ArchiveName: UTF8String;
    Archive: TJclDecompressArchive;
    ProcessDataProc: TProcessDataProcW;
  public
    procedure JclCompressionProgress(Sender: TObject; const Value, MaxValue: Int64); override;
    function JclCompressionExtract(Sender: TObject; AIndex: Integer;
      var AFileName: TFileName; var Stream: TStream; var AOwnsStream: Boolean): Boolean;
  end;

threadvar
  ProcessDataProcT: TProcessDataProcW;

function GetArchiveError(const E: Exception): Integer;
begin
  if E is EFOpenError then
    Result:= E_EOPEN
  else if E is EFCreateError then
    Result:= E_ECREATE
  else if E is EReadError then
    Result:= E_EREAD
  else if E is EWriteError then
    Result:= E_EWRITE
  else if E is ESevenZipAbort then
    Result:= E_EABORTED
  else
    Result:= E_UNKNOWN_FORMAT;
end;

function WinToDosTime(const WinTime: TFILETIME; var DosTime: Cardinal): LongBool;
var
  lft : Windows.TFILETIME;
begin
  Result:= Windows.FileTimeToLocalFileTime(@Windows.FILETIME(WinTime), @lft) and
           Windows.FileTimeToDosDateTime(@lft, @LongRec(Dostime).Hi, @LongRec(DosTime).Lo);
end;

function OpenArchiveW(var ArchiveData : tOpenArchiveDataW) : TArcHandle; stdcall;
var
  I: Integer;
  Handle: TSevenZipHandle;
  AFormats: TJclDecompressArchiveClassArray;
begin
  Handle:= TSevenZipHandle.Create;
  with Handle do
  begin
    Index:= 0;
    ArchiveName := UTF8Encode(WideString(ArchiveData.ArcName));
    AFormats := FindDecompressFormats(ArchiveName);
    for I := Low(AFormats) to High(AFormats) do
    begin
      Archive := AFormats[I].Create(ArchiveName, 0, False);
      try
        Archive.OnPassword:= JclCompressionPassword;
        Archive.OnProgress := JclCompressionProgress;

        Archive.OnExtract:= JclCompressionExtract;
        Archive.ListFiles;

        Count:= Archive.ItemCount;

        ArchiveData.OpenResult:= E_SUCCESS;

        Exit(TArcHandle(Handle));
      except
        on E: Exception do
        begin
          ArchiveData.OpenResult:= GetArchiveError(E);
          FreeAndNil(Archive);
          Continue;
        end;
      end;
    end;
    if (Archive = nil) then Free;
  end;
  Result:= 0;
end;

function ReadHeaderExW(hArcData : TArcHandle; var HeaderData: THeaderDataExW) : Integer; stdcall;
var
  Item: TJclCompressionItem;
  Handle: TSevenZipHandle absolute hArcData;
begin
  with Handle do
  begin
    if Index >= Count then Exit(E_END_ARCHIVE);
    Item:= Archive.Items[Index];
    HeaderData.FileName:= Item.PackedName;
    HeaderData.UnpSize:= Int64Rec(Item.FileSize).Lo;
    HeaderData.UnpSizeHigh:= Int64Rec(Item.FileSize).Hi;
    HeaderData.PackSize:= Int64Rec(Item.PackedSize).Lo;
    HeaderData.PackSizeHigh:= Int64Rec(Item.PackedSize).Hi;
    HeaderData.FileAttr:= Item.Attributes;
    WinToDosTime(Item.LastWriteTime, LongWord(HeaderData.FileTime));
    // Special case for BZip2, GZip and Xz archives
    if (HeaderData.FileName[0] = #0) then
    begin
      HeaderData.FileName:= GetNestedArchiveName(ArchiveName, Item);
    end;
  end;
  Result:= E_SUCCESS;
end;

function ProcessFileW(hArcData: TArcHandle; Operation: Integer; DestPath, DestName: PWideChar): Integer; stdcall;
var
  Handle: TSevenZipHandle absolute hArcData;
begin
  try
    with Handle do
    case Operation of
      PK_TEST,
      PK_EXTRACT:
        begin
          if Operation = PK_EXTRACT then
          begin
            if Assigned(DestPath) then
            begin
              FileName:= UTF8Encode(WideString(DestName));
              Directory:= IncludeTrailingPathDelimiter(UTF8Encode(WideString(DestPath)));
            end
            else begin
              Directory:= ExtractFilePath(UTF8Encode(WideString(DestName)));
              FileName:= ExtractFileName(UTF8Encode(WideString(DestName)));
            end;
          end;
          try
            Result:= E_SUCCESS;
            TJclSevenzipDecompressArchive(Archive).ExtractItem(Index, Directory, Operation = PK_TEST);
          except
            on E: Exception do
              Result:= GetArchiveError(E);
          end;
        end;
      else
        Result:= E_SUCCESS;
    end;
  finally
    Inc(Handle.Index);
  end;
end;

function CloseArchive(hArcData: TArcHandle): Integer; stdcall;
var
  Handle: TSevenZipHandle absolute hArcData;
begin
  Result:= E_SUCCESS;
  if (hArcData <> wcxInvalidHandle) then
  begin
    Handle.Archive.Free;
    Handle.Free;
  end;
end;

procedure SetChangeVolProcW(hArcData : TArcHandle; pChangeVolProc : TChangeVolProcW); stdcall;
begin

end;

procedure SetProcessDataProcW(hArcData : TArcHandle; pProcessDataProc : TProcessDataProcW); stdcall;
var
  Handle: TSevenZipHandle absolute hArcData;
begin
  if (hArcData = wcxInvalidHandle) then
    ProcessDataProcT:= pProcessDataProc
  else begin
    Handle.ProcessDataProc:= pProcessDataProc;
  end;
end;

function PackFilesW(PackedFile: PWideChar; SubPath: PWideChar;
  SrcPath: PWideChar; AddList: PWideChar; Flags: Integer): Integer; stdcall;
var
  I: Integer;
  Encrypt: Boolean;
  Password: WideString;
  FilePath: WideString;
  FileName: WideString;
  FileNameUTF8: UTF8String;
  Archive: TJclUpdateArchive;
  AProgress: TSevenZipUpdate;
  AFormats: TJclUpdateArchiveClassArray;
begin
  if (Flags and PK_PACK_MOVE_FILES) <> 0 then Exit(E_NOT_SUPPORTED);
  FileNameUTF8 := UTF8Encode(WideString(PackedFile));
  AFormats := FindUpdateFormats(FileNameUTF8);
  for I := Low(AFormats) to High(AFormats) do
  begin
    Archive := AFormats[I].Create(FileNameUTF8, 0, False);
    try
      AProgress:= TSevenZipUpdate.Create;
      Archive.OnPassword:= AProgress.JclCompressionPassword;
      Archive.OnProgress:= AProgress.JclCompressionProgress;

      if (Flags and PK_PACK_ENCRYPT) <> 0 then
      begin
        Encrypt:= Archive is TJcl7zUpdateArchive;
        if not ShowPasswordQuery(Encrypt, Password) then
          Exit(E_EABORTED)
        else begin
          Archive.Password:= Password;
          if Encrypt then TJcl7zUpdateArchive(Archive).SetEncryptHeader(True);
          if Archive is TJclZipUpdateArchive then TJclZipUpdateArchive(Archive).SetEncryptionMethod(emAES256);
        end;
      end;

      if (GetFileAttributesW(PackedFile) <> INVALID_FILE_ATTRIBUTES) then
      try
        Archive.ListFiles;
      except
        Continue;
      end;

      if Assigned(SubPath) then
      begin
        FilePath:= WideString(SubPath);
        if FilePath[Length(FilePath)] <> PathDelim then
          FilePath := FilePath + PathDelim;
      end;

      while True do
      begin
        FileName := WideString(AddList);
        FileNameUTF8:= UTF8Encode(WideString(SrcPath + FileName));
        if FileName[Length(FileName)] = PathDelim then
          Archive.AddDirectory(FilePath + FileName, FileNameUTF8)
        else
          Archive.AddFile(FilePath + FileName, FileNameUTF8);
        if (AddList + Length(FileName) + 1)^ = #0 then
          Break;
        Inc(AddList, Length(FileName) + 1);
      end;
      try
        Archive.Compress;
      except
        on E: Exception do
          Exit(GetArchiveError(E));
      end;
      Exit(E_SUCCESS);
    finally
      Archive.Free;
      AProgress.Free;
    end;
  end;
  Result:= E_NOT_SUPPORTED;
end;

function DeleteFilesW(PackedFile, DeleteList: PWideChar): Integer; stdcall;
var
  I: Integer;
  PathEnd : WideChar;
  FileList : PWideChar;
  FileName : WideString;
  FileNameUTF8 : UTF8String;
  Archive: TJclUpdateArchive;
  AProgress: TSevenZipUpdate;
  AFormats: TJclUpdateArchiveClassArray;
begin
  FileNameUTF8 := UTF8Encode(WideString(PackedFile));
  AFormats := FindUpdateFormats(FileNameUTF8);
  for I := Low(AFormats) to High(AFormats) do
  begin
    Archive := AFormats[I].Create(FileNameUTF8, 0, False);
    try
      AProgress:= TSevenZipUpdate.Create;
      Archive.OnPassword:= AProgress.JclCompressionPassword;
      Archive.OnProgress:= AProgress.JclCompressionProgress;

      try
        Archive.ListFiles;
      except
        Continue;
      end;

      // Parse file list.
      FileList := DeleteList;
      while FileList^ <> #0 do
      begin
        FileName := FileList;  // Convert PWideChar to WideString (up to first #0)
        PathEnd := (FileList + Length(FileName) - 1)^;
        // If ends with '.../*.*' or '.../' then delete directory.
        if (PathEnd = '*') or (PathEnd = PathDelim) then
          TJclSevenzipUpdateArchive(Archive).RemoveDirectory(WideExtractFilePath(FileName))
        else
          TJclSevenzipUpdateArchive(Archive).RemoveItem(FileName);

        FileList := FileList + Length(FileName) + 1; // move after filename and ending #0
        if FileList^ = #0 then
          Break;  // end of list
      end;
      try
        Archive.Compress;
      except
        on E: Exception do
          Exit(GetArchiveError(E));
      end;
      Exit(E_SUCCESS);
    finally
      Archive.Free;
      AProgress.Free;
    end;
  end;
  Result:= E_NOT_SUPPORTED;
end;

function CanYouHandleThisFileW(FileName: PWideChar): Boolean; stdcall;
begin
  Result:= FindDecompressFormats(UTF8Encode(WideString(FileName))) <> nil;
end;

procedure PackSetDefaultParams(dps: PPackDefaultParamStruct); stdcall;
var
  ModulePath: AnsiString;
begin
  // Load library from plugin path
  if GetModulePath(ModulePath) and FileExists(ModulePath + SevenzipDefaultLibraryName) then
  begin
    SevenzipLibraryName:= ModulePath + SevenzipDefaultLibraryName;
  end;
  // Process Xz files as archives
  GetArchiveFormats.RegisterFormat(TJclXzDecompressArchive);
  // Don't process PE files as archives
  GetArchiveFormats.UnregisterFormat(TJclPeDecompressArchive);
  // Try to load 7z.dll
  if not (Is7ZipLoaded or Load7Zip) then
  begin
    MessageBoxW(0, PWideChar(UTF8Decode(rsSevenZipLoadError)), 'SevenZip', MB_OK or MB_ICONERROR);
  end;
end;

{ TSevenZipUpdate }

procedure TSevenZipUpdate.JclCompressionPassword(Sender: TObject;
  var Password: WideString);
var
  Encrypt: Boolean = False;
begin
  if not ShowPasswordQuery(Encrypt, Password) then
    raise ESevenZipAbort.Create(EmptyStr);
end;

procedure TSevenZipUpdate.JclCompressionProgress(Sender: TObject; const Value,
  MaxValue: Int64);
var
  Percent: Int64;
  Archive: TJclUpdateArchive absolute Sender;
begin
  if Assigned(ProcessDataProcT) then
  begin
    Percent:= 1000 + (Value * 100) div MaxValue;
    // If the user has clicked on Cancel, the function returns zero
    Archive.CancelCurrentOperation:= ProcessDataProcT(PWideChar(Archive.Items[Archive.CurrentItemIndex].PackedName), -Percent) = 0;
  end;
end;

{ TSevenZipHandle }

procedure TSevenZipHandle.JclCompressionProgress(Sender: TObject; const Value,
  MaxValue: Int64);
var
  Percent: Int64;
  Archive: TJclDecompressArchive absolute Sender;
begin
  if Assigned(ProcessDataProc) then
  begin
    Percent:= 1000 + (Value * 100) div MaxValue;
    // If the user has clicked on Cancel, the function returns zero
    Archive.CancelCurrentOperation:= ProcessDataProc(PWideChar(Archive.Items[Archive.CurrentItemIndex].PackedName), -Percent) = 0;
  end;
end;

function TSevenZipHandle.JclCompressionExtract(Sender: TObject; AIndex: Integer;
  var AFileName: TFileName; var Stream: TStream; var AOwnsStream: Boolean): Boolean;
begin
  Result:= True;
  AFileName:= Directory + FileName;
end;

end.

