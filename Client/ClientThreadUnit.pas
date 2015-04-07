unit ClientThreadUnit;

interface

uses
  Classes {$IFDEF MSWINDOWS} , Windows {$ENDIF}, U_GlobalDataUnit,
  SysUtils, synsock, blcksock;

type
  TClientThread = class(TThread)
  private
    FIP: string; 
    FPort: string;
    FDateTimeOnline: TDatetime; 
    FMode: TClientMode;
    FDeviceID: Word;
    procedure SetName;    
  protected
    procedure Execute; override;
  public
    constructor Create(const aDateTimeOnline: TDatetime; aMode: TClientMode;
      const aIP, aPort: string; aDeviceID: Word);
  end;

implementation
uses Forms;

{ Important: Methods and properties of objects in visual components can only be
  used in a method called using Synchronize, for example,

      Synchronize(UpdateCaption);

  and UpdateCaption could look like,

    procedure TClientThread.UpdateCaption;
    begin
      Form1.Caption := 'Updated in a thread';
    end; }

{$IFDEF MSWINDOWS}
type
  TThreadNameInfo = record
    FType: LongWord;     // must be 0x1000
    FName: PChar;        // pointer to name (in user address space)
    FThreadID: LongWord; // thread ID (-1 indicates caller thread)
    FFlags: LongWord;    // reserved for future use, must be zero
  end;
{$ENDIF}

{ TClientThread }

procedure TClientThread.SetName;
{$IFDEF MSWINDOWS}
var
  ThreadNameInfo: TThreadNameInfo;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  ThreadNameInfo.FType := $1000;
  ThreadNameInfo.FName := PChar('ClientN' + IntToStr(FDeviceID));
  ThreadNameInfo.FThreadID := $FFFFFFFF;
  ThreadNameInfo.FFlags := 0;

  try
    RaiseException( $406D1388, 0, sizeof(ThreadNameInfo) div sizeof(LongWord), @ThreadNameInfo );
  except
  end;
{$ENDIF}
end;

constructor TClientThread.Create(const aDateTimeOnline: TDatetime;
  aMode: TClientMode; const aIP, aPort: string; aDeviceID: Word);
begin
  FIP := aIP; 
  FPort := aPort;
  FDateTimeOnline := aDateTimeOnline;
  FMode := aMode;  
  FDeviceID := aDeviceID;
  FreeOnTerminate := true;
  inherited Create;
  //Priority := tpLower;
end;

procedure TClientThread.Execute;
var
  i: Integer;
  zAutoIncValue: word;
  tcpSock: TTCPBlockSocket;
  zMemStream: TStreamHelper;
  zClientResult: PClentInfo;
  zCanWrite: boolean;
begin
  SetName;
  { Place thread code here }
  zClientResult := GetPClentInfo( FDeviceID, cmDefaultMode, 0, csWaiting);
  //PostMessage(Application.MainFormHandle, WM_TCPClientNotify, Integer(zClientResult), 0);
  IOTransactDone(zClientResult);

  // ��� ���������� �������
  while (not Terminated) and (Now < FDateTimeOnline) do
    Sleep(10);
  
  zMemStream := TStreamHelper.Create;
  tcpSock := TTCPBlockSocket.Create;
  tcpSock.ConnectionTimeout := cClientConnectionTimeout;
  tcpSock.SetTimeout(cSetTimeout);
  tcpSock.SocksTimeout := cSocketsTimeOut;
  tcpSock.SetLinger(false, cLinger);
  tcpSock.RaiseExcept := false;
  try    
    try
      // �������� �������� �����
      zMemStream.WriteWord(FDeviceID);
      zAutoIncValue := 0;
      for I := zMemStream.Size div 2 to cDefaultPacketSize div 2 do
      begin      
        zMemStream.WriteWord(zAutoIncValue);
        Inc(zAutoIncValue);
      end;      
      
      zClientResult := GetPClentInfo( FDeviceID, cmDefaultMode, 0, csTryToConnect);
      //SendMessage(Application.MainFormHandle, WM_TCPClientNotify, Integer(zClientResult), 0);
      IOTransactDone(zClientResult);
      zCanWrite := false;
      // ������������
      for I := 0 to 30 do
      begin
        tcpSock.Connect(FIP, FPort);
        //zCanWrite := tcpSock.CanWrite(cSocketsTimeOut);
        if (Terminated or (tcpSock.LastError = 0) or (zCanWrite)) then
          break;
        tcpSock.CloseSocket;
        tcpSock.ResetLastError;
        sleep(cClientConnectionTimeout);
      end;
      if ((tcpSock.LastError = 0) or (zCanWrite)) then
      begin
        tcpSock.RaiseExcept := true;
        zClientResult := GetPClentInfo( FDeviceID, cmDefaultMode, 0, csConnected);
        IOTransactDone(zClientResult);

        // ��������� �����
        zMemStream.Position := 0;
        tcpSock.SendStream(zMemStream);
        zMemStream.Clear;
        zClientResult := GetPClentInfo( FDeviceID, cmDefaultMode, 0, csInTransaction);
        IOTransactDone(zClientResult);

        // �������� ����� �� �������
        tcpSock.RecvStream(zMemStream, cClientTimeout);
        zMemStream.Position := 0;
        // ������������ �����
        FMode := TClientMode(zMemStream.ReadByte);
        // ����� �����
        zMemStream.Clear;
        zMemStream.WriteWord(FDeviceID);
        zMemStream.WriteWord(255);
        zMemStream.Position := 0;
        case FMode of
          cmDefaultMode:begin
            tcpSock.SendStream(zMemStream);
          end;
          cmWithUpdateTransaction:begin
            tcpSock.SendStream(zMemStream);
          end;
        end;
        zClientResult := GetPClentInfo( FDeviceID, cmDefaultMode, 0, csDone);
        IOTransactDone(zClientResult);

      end else
      begin
        zClientResult := GetPClentInfo( FDeviceID, cmDefaultMode, 0, csConnectError);
        IOTransactDone(zClientResult);
      end;
    finally
      tcpSock.Free;
      zMemStream.Free;
    end;
  except
    on E: ESynapseError do
    begin
      zClientResult := GetPClentInfo( FDeviceID, cmDefaultMode, 0, csConnectError);
      IOTransactDone(zClientResult);
    end;
  end;
end;

end.
