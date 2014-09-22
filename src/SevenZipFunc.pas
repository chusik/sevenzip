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
  Windows, SysUtils, Classes, JclCompression;

type

  { TSevenZipHandle }

  TSevenZipHandle = class
    Index,
    Count: LongWord;
    FileName: AnsiString;
    Directory: AnsiString;
    Archive: TJclCompressionArchive;
    ProcessDataProc: TProcessDataProcW;
    procedure JclCompressionProgress(Sender: TObject; const Value, MaxValue: Int64);
    function JclCompressionExtract(Sender: TObject; AIndex: Integer;
      var AFileName: TFileName; var Stream: TStream; var AOwnsStream: Boolean): Boolean;
  end;

threadvar
  ProcessDataProcT: TProcessDataProcW;



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

    AFormats := GetArchiveFormats.FindDecompressFormats(ArchiveData.ArcName);

    for I := Low(AFormats) to High(AFormats) do
    begin
      Archive := AFormats[I].Create(ArchiveData.ArcName, 0, False);
      try
        Archive.OnProgress := JclCompressionProgress;

        if Archive is TJclDecompressArchive then
        begin
          TJclDecompressArchive(Archive).OnExtract:= JclCompressionExtract;
          TJclDecompressArchive(Archive).ListFiles
        end
        else
        if Archive is TJclUpdateArchive then
          TJclUpdateArchive(Archive).ListFiles;

        Count:= Archive.ItemCount;

        Exit(TArcHandle(Handle));
      except
        //CloseAllArchive;
      end;
    end;
  end;
  Result:= wcxInvalidHandle;
end;

function ReadHeaderExW(hArcData : TArcHandle; var HeaderData: THeaderDataExW) : Integer; stdcall;
var
  Item: TJclCompressionItem;
  Handle: TSevenZipHandle absolute hArcData;
begin
  with Handle do
  begin
    if Index >= Count then
    begin
      if Archive is TJclDecompressArchive then
        TJclDecompressArchive(Archive).ExtractSelected(Directory, True)
      else
      if Archive is TJclUpdateArchive then
        TJclUpdateArchive(Archive).ExtractSelected(Directory, True);

      Result:= E_END_ARCHIVE;
      Exit;
    end;
    Item:= Archive.Items[Index];
    HeaderData.FileName:= Item.PackedName;
    HeaderData.UnpSize:= Int64Rec(Item.FileSize).Lo;
    HeaderData.UnpSizeHigh:= Int64Rec(Item.FileSize).Hi;
    HeaderData.PackSize:= Int64Rec(Item.PackedSize).Lo;
    HeaderData.PackSizeHigh:= Int64Rec(Item.PackedSize).Hi;
    HeaderData.FileAttr:= Item.Attributes;
  end;
  Result:= E_SUCCESS;
end;

function ProcessFileW(hArcData : TArcHandle; Operation : Integer; DestPath, DestName : PWideChar) : Integer;stdcall;
var
  FileSize: Int64;
  FileHandle: THandle;
  Handle: TSevenZipHandle absolute hArcData;
begin
  try
    with Handle do
    case Operation of
      PK_EXTRACT:
        begin
          if Assigned(DestPath) then
          begin
            FileName:= DestName;
            Directory:= IncludeTrailingPathDelimiter(DestPath);
          end
          else begin
            Directory:= ExtractFilePath(DestName);
            FileName:= ExtractFileName(DestName);
          end;
          Archive.Items[Index].Selected := True;

           // Result:= E_EWRITE
//          else
            Result:= E_SUCCESS;
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

{
function ProgressCallback(sender: Pointer; total: boolean; value: int64): HRESULT; stdcall;
var
  Return: Integer;
  Handle: TSevenZipHandle absolute sender;
begin
  if (Sender = nil) then
    Return:= ProcessDataProcT(nil, Value)
  else with Handle do
    Return:= ProcessDataProc(PWideChar(Archive.ItemPath[Index]), Value);

  if (Return <> 0) then
    Result := S_OK
  else
    Result := E_FAIL;
end;
}

procedure SetProcessDataProcW(hArcData : TArcHandle; pProcessDataProc : TProcessDataProcW); stdcall;
var
  Handle: TSevenZipHandle absolute hArcData;
begin
  if (hArcData = wcxInvalidHandle) then
    ProcessDataProcT:= pProcessDataProc
  else begin
    Handle.ProcessDataProc:= pProcessDataProc;
//    Handle.Archive.SetProgressCallback(Handle, @ProgressCallback);
  end;
end;

function PackFilesW(PackedFile: PWideChar; SubPath: PWideChar;
  SrcPath: PWideChar; AddList: PWideChar; Flags: Integer): Integer; stdcall;
var
  I: Integer;
  Archive: TJclCompressionArchive;
  AFormats: TJclCompressArchiveClassArray;
var

  FilePath: WideString;
  FileName: WideString;
  sPassword: AnsiString;

begin

    AFormats := GetArchiveFormats.FindCompressFormats(PackedFile);

    for I := Low(AFormats) to High(AFormats) do
    begin
      Archive := AFormats[I].Create(PackedFile, 0, False);
      try
        if not (Archive is TJclCompressArchive) then Continue;

//        Archive.OnProgress := JclCompressionProgress;


        FilePath:= WideString(SubPath);
        while True do
        begin
          FileName := WideString(AddList);
          (Archive as TJclCompressArchive).AddFile(FileName, SrcPath + FilePath + FileName);
          if (AddList + Length(FileName) + 1)^ = #0 then
            Break;
          Inc(AddList, Length(FileName) + 1);
        end;
        (Archive as TJclCompressArchive).Compress;
        Archive.Free;

        Exit(E_SUCCESS);
      except
        //CloseAllArchive;
      end;
    end;

  Result:= E_NOT_SUPPORTED;
end;

function DeleteFilesW(PackedFile, DeleteList: PWideChar): Integer; stdcall;
var
  I: Integer;
  Archive: TJclUpdateArchive;
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
        if not (Archive is TJclUpdateArchive) then Continue;

        Archive.ListFiles;

//        Archive.OnProgress := JclCompressionProgress;

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
(Archive as TJclUpdateArchive).Compress;


        Archive.Free;

        Exit(E_SUCCESS);
      except
        //CloseAllArchive;
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

{ TSevenZipHandle }

procedure TSevenZipHandle.JclCompressionProgress(Sender: TObject; const Value,
  MaxValue: Int64);
begin

end;

function TSevenZipHandle.JclCompressionExtract(Sender: TObject; AIndex: Integer;
  var AFileName: TFileName; var Stream: TStream; var AOwnsStream: Boolean
  ): Boolean;
begin
  Result:= True;
  AFileName:= Directory + FileName;
end;

end.

