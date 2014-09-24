unit SevenZipAdv;

{$mode delphi}

interface

uses
  Classes, SysUtils, SevenZip, JclCompression;

type
  TBytes = array of Byte;

type

   { TArchiveFormat }

   TArchiveFormat = class
     Name: UnicodeString;
     Extension: UnicodeString;
     AddExtension: UnicodeString;
     Update: WordBool;
     KeepName: WordBool;
     ClassID: TGUID;
     StartSignature: TBytes;
   end;

  { TJclSevenzipDecompressArchiveHelper }

  TJclSevenzipDecompressArchiveHelper = class helper for TJclSevenzipDecompressArchive
    procedure ExtractItem(Index: Cardinal; const ADestinationDir: UTF8String; Verify: Boolean);
  end;

function FindDecompressFormats(const AFileName: TFileName): TJclDecompressArchiveClassArray;

implementation

uses
  ActiveX, Windows, JclSysUtils, LazFileUtils;

type
  TArchiveFormats = array of TArchiveFormat;
  TJclSevenzipCompressArchiveClass = class of TJclSevenzipCompressArchive;

type
  TArchiveFormatCache = record
    ArchiveName: UTF8String;
    ArchiveClassArray: TJclDecompressArchiveClassArray;
  end;

var
  ArchiveFormatsX: TArchiveFormats;

var
  ArchiveFormatCache: TArchiveFormatCache;

function ReadStringProp(FormatIndex: Cardinal; PropID: TPropID;
  out Value: UnicodeString): LongBool;
var
  PropSize: Cardinal;
  PropValue: TPropVariant;
begin
  Result:= Succeeded(GetHandlerProperty2(FormatIndex, PropID, PropValue));
  Result:= Result and (PropValue.vt = VT_BSTR);
  if Result then
  try
    PropSize:= SysStringByteLen(PropValue.bstrVal);
    SetLength(Value, PropSize div SizeOf(WideChar));
    CopyMemory(PWideChar(Value), PropValue.bstrVal, PropSize);
  finally
    SysFreeString(PropValue.bstrVal);
  end;
end;

function ReadBooleanProp(FormatIndex: Cardinal;
  PropID: TPropID; out Value: WordBool): LongBool;
var
  PropSize: Cardinal;
  PropValue: TPropVariant;
begin
  Result:= Succeeded(GetHandlerProperty2(FormatIndex, PropID, PropValue));
  Result:= Result and (PropValue.vt = VT_BOOL);
  if Result then Value:= PropValue.boolVal;
end;

procedure LoadArchiveFormats(var ArchiveFormats: TArchiveFormats);
var
  J: Integer;
  Data: PByte;
  Idx: Integer = 0;
  PropValue: TPropVariant;
  ArchiveFormat: TArchiveFormat;
  Index, NumberOfFormats: Cardinal;
begin
  if (not Is7ZipLoaded) and (not Load7Zip) then Exit;

  if not Succeeded(GetNumberOfFormats(@NumberOfFormats)) then
    Exit;
  SetLength(ArchiveFormats, NumberOfFormats);
  for Index := Low(ArchiveFormats) to High(ArchiveFormats) do
  begin
    // Archive format GUID
    GetHandlerProperty2(Index, kClassID, PropValue);
    if PropValue.vt = VT_BSTR then
    try
      if SysStringByteLen(PropValue.bstrVal) <> SizeOf(TGUID) then
        Continue
      else begin
        ArchiveFormat:= TArchiveFormat.Create;
        ArchiveFormat.ClassID:= PGUID(PropValue.bstrVal)^;
      end;
    finally
      SysFreeString(PropValue.bstrVal);
    end;
    // Archive format signature
    GetHandlerProperty2(Index, kStartSignature, PropValue);
    if PropValue.vt = VT_BSTR then
    try
      SetLength(ArchiveFormat.StartSignature, SysStringByteLen(PropValue.bstrVal));
      Data:= PByte(PropValue.bstrVal);
      for J:= Low(ArchiveFormat.StartSignature) to High(ArchiveFormat.StartSignature) do
       ArchiveFormat.StartSignature[J]:= Data[J];
    finally
      SysFreeString(PropValue.bstrVal);
    end;

    ReadStringProp(Index, kArchiveName, ArchiveFormat.Name);
    ReadStringProp(Index, kExtension, ArchiveFormat.Extension);
    ReadStringProp(Index, kAddExtension, ArchiveFormat.AddExtension);
    ReadBooleanProp(Index, kUpdate, ArchiveFormat.Update);
    ReadBooleanProp(Index, kKeepName, ArchiveFormat.KeepName);

    ArchiveFormats[Idx]:= ArchiveFormat;
    Inc(Idx);
  end;
  SetLength(ArchiveFormats, Idx);
end;

function Contains(const ArrayToSearch: TJclDecompressArchiveClassArray; const ArchiveClass: TJclDecompressArchiveClass): Boolean;
var
  Index: Integer;
begin
  for Index := Low(ArrayToSearch) to High(ArrayToSearch) do
    if ArrayToSearch[Index] = ArchiveClass then
      Exit(True);
  Result := False;
end;

function FindDecompressFormat(const ClassID: TGUID): TJclDecompressArchiveClass;
var
  Index: Integer;
  ArchiveClass: TJclSevenzipCompressArchiveClass;
begin
  for Index:= 0 to GetArchiveFormats.DecompressFormatCount - 1 do
  begin
    ArchiveClass:= TJclSevenzipCompressArchiveClass(GetArchiveFormats.DecompressFormats[Index]);
    if GUIDEquals(ClassID, ArchiveClass.ArchiveCLSID) then
      Exit(GetArchiveFormats.DecompressFormats[Index]);
  end;
  Result:= nil;
end;

function FindDecompressFormats(const AFileName: TFileName): TJclDecompressArchiveClassArray;
const
  BufferSize = 524288;
var
  AFile: THandle;
  I, Idx, Index: Integer;
  ArchiveFormat: TArchiveFormat;
  ArchiveClass: TJclDecompressArchiveClass;
  Buffer: array[0..Pred(BufferSize)] of Byte;
begin
  // Try to find archive type in cache
  if ArchiveFormatCache.ArchiveName = AFileName then
    Exit(ArchiveFormatCache.ArchiveClassArray)
  else begin
    ArchiveFormatCache.ArchiveName:= AFileName;
    SetLength(ArchiveFormatCache.ArchiveClassArray, 0);
  end;

  Result:= GetArchiveFormats.FindDecompressFormats(AFileName);

  if Length(ArchiveFormatsX) = 0 then LoadArchiveFormats(ArchiveFormatsX);

  AFile:= FileOpenUTF8(AFileName, fmOpenRead or fmShareDenyNone);
  if AFile = feInvalidHandle then Exit(nil);
  try
   if FileRead(AFile, Buffer, SizeOf(Buffer)) = 0 then
     Exit(nil);
  finally
    FileClose(AFile);
  end;

  for Index := Low(ArchiveFormatsX) to High(ArchiveFormatsX) do
  begin
    ArchiveFormat:= ArchiveFormatsX[Index];

    // Skip container types
    if GUIDEquals(ArchiveFormat.ClassID, CLSID_CFormatPe) then Continue;
    if GUIDEquals(ArchiveFormat.ClassID, CLSID_CFormatIso) then Continue;
    if GUIDEquals(ArchiveFormat.ClassID, CLSID_CFormatUdf) then Continue;

    if Length(ArchiveFormat.StartSignature) = 0 then Continue;
    for Idx:= 0 to Pred(BufferSize) - Length(ArchiveFormat.StartSignature) do
    begin
      if CompareMem(@Buffer[Idx], @ArchiveFormat.StartSignature[0], Length(ArchiveFormat.StartSignature)) then
      begin
        ArchiveClass:= FindDecompressFormat(ArchiveFormat.ClassID);
        if Assigned(ArchiveClass) and not Contains(Result, ArchiveClass) then
        begin
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := ArchiveClass;
        end;
        Break;
      end;
    end;
  end;
  // Save archive type in cache
  ArchiveFormatCache.ArchiveClassArray:= Result;
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

end.

