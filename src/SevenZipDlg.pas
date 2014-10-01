unit SevenZipDlg;

{$mode delphi}

interface

uses
  Classes, SysUtils, Windows;

function ShowPasswordQuery(var Encrypt: Boolean; var Password: WideString): Boolean;

implementation

{$R *.res}

const
  IDC_PASSWORD = 1001;
  IDC_SHOW_PASSWORD = 1002;
  IDC_ENCRYPT_HEADER = 0;

type
  PPasswordData = ^TPasswordData;
  TPasswordData = record
    EncryptHeader: Boolean;
    Password: array[0..MAX_PATH] of WideChar;
  end;

function PasswordDialog(hwndDlg: HWND; uMsg: UINT; wParam: WPARAM; lParam: LPARAM): INT_PTR; stdcall;
var
  PasswordChar: WideChar;
  PasswordData: PPasswordData;
begin
  PasswordData:= PPasswordData(GetWindowLongPtr(hwndDlg, GWLP_USERDATA));
  case uMsg of
    WM_INITDIALOG:
    begin
      PasswordData:= PPasswordData(lParam);
      SetWindowLongPtr(hwndDlg, GWLP_USERDATA, LONG_PTR(lParam));
      SetDlgItemTextW(hwndDlg, IDC_PASSWORD, PasswordData^.Password);
      SendDlgItemMessage(hwndDlg, IDC_PASSWORD, EM_SETLIMITTEXT, MAX_PATH, 0);
      EnableWindow(GetDlgItem(hwndDlg, IDC_ENCRYPT_HEADER), PasswordData^.EncryptHeader);
      Exit(1);
    end;
    WM_COMMAND:
    begin
      case LOWORD(wParam) of
       IDOK:
       begin
         PasswordData^.EncryptHeader:= IsDlgButtonChecked(hwndDlg, IDC_ENCRYPT_HEADER) <> 0;
         GetDlgItemTextW(hwndDlg, IDC_PASSWORD, PasswordData^.Password, MAX_PATH);
   	 EndDialog(hwndDlg, IDOK);
       end;
       IDCANCEL:
         EndDialog(hwndDlg, IDCANCEL);
       IDC_SHOW_PASSWORD:
       begin
         if IsDlgButtonChecked(hwndDlg, IDC_SHOW_PASSWORD) <> 0 then
           PasswordChar:= #0
         else
           PasswordChar:= '*';
      	SendDlgItemMessageW(hwndDlg, IDC_PASSWORD, EM_SETPASSWORDCHAR, Ord(PasswordChar), 0);
       end;
      end;
    end;
  end;
  Result:= 0;
end;

function ShowPasswordQuery(var Encrypt: Boolean; var Password: WideString): Boolean;
var
  PasswordData: TPasswordData;
begin
  PasswordData.Password:= Password;
  PasswordData.EncryptHeader:= Encrypt;
  Result:= (DialogBoxParam(hInstance, 'DIALOG_PWD', 0, @PasswordDialog, LPARAM(@PasswordData)) = IDOK);
  if Result then
  begin
    Password:= PasswordData.Password;
    Encrypt:= PasswordData.EncryptHeader;
  end;
end;

end.

