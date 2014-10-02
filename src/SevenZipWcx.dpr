library SevenZipWcx;

uses
  Classes,
  SevenZipFunc, SevenZipDlg,
  WcxPlugin, SevenZipAdv;

function OpenArchive(var ArchiveData : tOpenArchiveData) : TArcHandle; stdcall;
begin
  Result:= wcxInvalidHandle;
  ArchiveData.OpenResult:= E_NOT_SUPPORTED;
end;

function ReadHeader(hArcData : TArcHandle; var HeaderData: THeaderData) : Integer; stdcall;
begin
  Result:= E_NOT_SUPPORTED;
end;

function ProcessFile (hArcData : TArcHandle; Operation : Integer; DestPath, DestName : PAnsiChar) : Integer; stdcall;
begin
  Result:= E_NOT_SUPPORTED;
end;

procedure SetChangeVolProc (hArcData : TArcHandle; pChangeVolProc : PChangeVolProc); stdcall;
begin
end;

procedure SetProcessDataProc (hArcData : TArcHandle; pProcessDataProc : TProcessDataProc); stdcall;
begin
end;

function GetBackgroundFlags: Integer; stdcall;
begin
  Result:= BACKGROUND_UNPACK or BACKGROUND_PACK;
end;

function GetPackerCaps : Integer; stdcall;
begin
  Result := PK_CAPS_NEW or PK_CAPS_DELETE  or PK_CAPS_MODIFY
         or PK_CAPS_MULTIPLE or PK_CAPS_OPTIONS or PK_CAPS_BY_CONTENT
         or PK_CAPS_ENCRYPT;
end;

exports
  { Mandatory }
  OpenArchive,
  OpenArchiveW,
  ReadHeader,
  ReadHeaderExW,
  ProcessFile,
  ProcessFileW,
  CloseArchive,
  SetChangeVolProc,
  SetChangeVolProcW,
  SetProcessDataProc,
  SetProcessDataProcW,
  { Optional }
  PackFilesW,
  DeleteFilesW,
  GetPackerCaps,
  GetBackgroundFlags,
  PackSetDefaultParams,
  CanYouHandleThisFileW
  ;

{$R *.res}

begin
end.

