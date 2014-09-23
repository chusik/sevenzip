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

implementation

uses
  JwaWinBase, Windows, SysUtils, Classes, JclCompression, sevenzip;

type

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
    Archive: TJclDecompressArchive;
    ProcessDataProc: TProcessDataProcW;
  public
    procedure JclCompressionProgress(Sender: TObject; const Value, MaxValue: Int64); override;
    function JclCompressionExtract(Sender: TObject; AIndex: Integer;
      var AFileName: TFileName; var Stream: TStream; var AOwnsStream: Boolean): Boolean;
  end;

  { TJclSevenzipDecompressArchiveHelper }

  TJclSevenzipDecompressArchiveHelper = class helper for TJclSevenzipDecompressArchive
    procedure ExtractItem(Index: Cardinal; const ADestinationDir: UTF8String; Verify: Boolean);
  end;

threadvar
  ProcessDataProcT: TProcessDataProcW;

function ExceptToError(const E: Exception): Integer;
begin
  if E is EFOpenError then
    Result:= E_EOPEN
  else if E is EFCreateError then
    Result:= E_ECREATE
  else if E is EReadError then
    Result:= E_EREAD
  else if E is EWriteError then
    Result:= E_EWRITE
  else
    Result:= E_BAD_DATA;
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
  FileNameUTF8: UTF8String;
  AFormats: TJclDecompressArchiveClassArray;
begin
  Handle:= TSevenZipHandle.Create;
  with Handle do
  begin
    Index:= 0;
    try
      FileNameUTF8 := UTF8Encode(WideString(ArchiveData.ArcName));
      AFormats := GetArchiveFormats.FindDecompressFormats(FileNameUTF8);
      for I := Low(AFormats) to High(AFormats) do
      begin
        Archive := AFormats[I].Create(FileNameUTF8, 0, False);
        try
          Archive.OnPassword:= JclCompressionPassword;
          Archive.OnProgress := JclCompressionProgress;

          Archive.OnExtract:= JclCompressionExtract;
          Archive.ListFiles;

          Count:= Archive.ItemCount;

          Exit(TArcHandle(Handle));
        except
          on E: exception do
          begin
            ArchiveData.ArcName:= PWideChar(WideString(E.Message));
            Archive.Free;
            Free;
          end;
        end;
      end;
    except
      Free;
    end;
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
  end;
  Result:= E_SUCCESS;
end;

function ProcessFileW(hArcData: TArcHandle; Operation: Integer; DestPath, DestName: PWideChar): Integer; stdcall;
var
  FileHandle: THandle;
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
              Result:= ExceptToError(E);
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
  FilePath: WideString;
  FileName: WideString;
  FileNameUTF8: UTF8String;
  Archive: TJclUpdateArchive;
  AProgress: TSevenZipUpdate;
  AFormats: TJclUpdateArchiveClassArray;
begin
  FileNameUTF8 := UTF8Encode(WideString(PackedFile));
  AFormats := GetArchiveFormats.FindUpdateFormats(FileNameUTF8);
  for I := Low(AFormats) to High(AFormats) do
  begin
    Archive := AFormats[I].Create(FileNameUTF8, 0, False);
    try
      AProgress:= TSevenZipUpdate.Create;
      Archive.OnPassword:= AProgress.JclCompressionPassword;
      Archive.OnProgress:= AProgress.JclCompressionProgress;

      if (GetFileAttributesW(PackedFile) <> INVALID_FILE_ATTRIBUTES) then
        Archive.ListFiles;

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
          Exit(ExceptToError(E));
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
  Archive: TJclUpdateArchive;
  AProgress: TSevenZipUpdate;
  AFormats: TJclUpdateArchiveClassArray;
var

 pFileName : PWideChar;
 FileName : WideString;
 FileNameUTF8 : UTF8String;

begin

    AFormats := GetArchiveFormats.FindUpdateFormats(PackedFile);

    for I := Low(AFormats) to High(AFormats) do
    begin
      Archive := AFormats[I].Create(PackedFile, 0, False);
      try
        AProgress:= TSevenZipUpdate.Create;
        Archive.OnPassword:= AProgress.JclCompressionPassword;
        Archive.OnProgress:= AProgress.JclCompressionProgress;

        Archive.ListFiles;

// Parse file list.
pFileName := DeleteList;
while pFileName^ <> #0 do
begin
  FileName := pFileName;    // Convert PWideChar to WideString (up to first #0).

  // If ends with '.../*.*' or '.../' then delete directory.
 // if StrEndsWith(FileNameUTF8, PathDelim + '*.*') or
 //    StrEndsWith(FileNameUTF8, PathDelim)
 // then
 //   (Archive as TJclUpdateArchive).RemoveItem(ExtractFilePath(FileName));
 // else
    (Archive as TJclUpdateArchive).RemoveItem(FileName);

  pFileName := pFileName + Length(FileName) + 1; // move after filename and ending #0
  if pFileName^ = #0 then
    Break;  // end of list
end;
try
Archive.Compress;
except
  on E: Exception do
    FileNameUTF8:= E.Message;
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
var
  AFormats: TJclDecompressArchiveClassArray;
begin
  AFormats := GetArchiveFormats.FindDecompressFormats(FileName);
  Result:= Length(AFormats) > 0;
end;

{ TJclSevenzipDecompressArchiveHelper }

procedure TJclSevenzipDecompressArchiveHelper.ExtractItem(Index: Cardinal; const ADestinationDir: UTF8String; Verify: Boolean);
var
  AExtractCallback: IArchiveExtractCallback;
begin
  CheckNotDecompressing;

  FDecompressing := True;
  FDestinationDir := ADestinationDir;
  AExtractCallback := TJclSevenzipExtractCallback.Create(Self);
  try
    OpenArchive;

    SevenzipCheck(InArchive.Extract(@Index, 1, Cardinal(Verify), AExtractCallback));
    CheckOperationSuccess;
  finally
    FDestinationDir := '';
    FDecompressing := False;
    AExtractCallback := nil;
  end;
end;

{ TSevenZipUpdate }

procedure TSevenZipUpdate.JclCompressionPassword(Sender: TObject;
  var Password: WideString);
begin
  Password:= '123';
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
    ProcessDataProcT(PWideChar(Archive.Items[Archive.CurrentItemIndex].PackedName), -Percent);
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
    ProcessDataProc(PWideChar(Archive.Items[Archive.CurrentItemIndex].PackedName), -Percent);
  end;
end;

function TSevenZipHandle.JclCompressionExtract(Sender: TObject; AIndex: Integer;
  var AFileName: TFileName; var Stream: TStream; var AOwnsStream: Boolean): Boolean;
begin
  Result:= True;
  AFileName:= Directory + FileName;
end;

end.

