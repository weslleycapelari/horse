unit Tests.Horse.Request;

interface

{$IF DEFINED(FPC)}
  {$MODE DELPHI}{$H+}
{$ENDIF}

uses
  DUnitX.TestFramework, Horse, Horse.Commons, Horse.Request, Horse.Response,
  System.SysUtils, System.Classes, RESTRequest4D.Request;

type
  [TestFixture]
  THorseRequestTest = class(TObject)
  private
    
    procedure StartServer;
    procedure StopServer;
    procedure RegisterRoutes;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestPayloadWithinLimit;

    [Test]
    procedure TestPayloadExceedsLimit;
  end;

implementation

{ THorseRequestTest }

procedure THorseRequestTest.Setup;
begin
  THorse.MaxPayloadSize := 1024;
  RegisterRoutes;
end;

procedure THorseRequestTest.TearDown;
begin
  THorse.MaxPayloadSize := 10485760; // Restaura padrão de 10 MB
  THorse.Reset;
end;

procedure THorseRequestTest.RegisterRoutes;
begin
  // Rota de teste de payload
  THorse.Post('/payload-test',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    var
      LBody: string;
    begin
      // A leitura de Req.Body aciona o GetBody, que é onde a verificação deve ocorrer
      LBody := Req.Body;
      Res.Send('{"received": ' + IntToStr(Length(LBody)) + '}').Status(THTTPStatus.Ok);
    end);
end;

procedure THorseRequestTest.StartServer;
begin
  if not THorse.IsRunning then
  begin
    TThread.CreateAnonymousThread(
      procedure
      begin
        THorse.Listen(9025);
      end).Start;
    TThread.Sleep(200); // Aguarda inicialização do servidor
  end;
end;

procedure THorseRequestTest.StopServer;
begin
  THorse.StopListen;
  TThread.Sleep(200); // Aguarda parada do servidor
end;

procedure THorseRequestTest.TestPayloadWithinLimit;
var
  LResponse: IResponse;
  LPayload: string;
begin
  StartServer;
  try
    // Payload de 500 bytes (menor que o limite de 1024)
    LPayload := '{"value": "' + StringOfChar('A', 480) + '"}';

    LResponse := TRequest.New.BaseURL('http://localhost:9025/payload-test')
      .Accept('application/json')
      .AddBody(LPayload)
      .Post;

    Assert.AreEqual(200, LResponse.StatusCode);
  finally
    StopServer;
  end;
end;

procedure THorseRequestTest.TestPayloadExceedsLimit;
var
  LResponse: IResponse;
  LPayload: string;
begin
  StartServer;
  try
    // Payload de 2000 bytes (maior que o limite de 1024)
    LPayload := '{"value": "' + StringOfChar('A', 1980) + '"}';

    LResponse := TRequest.New.BaseURL('http://localhost:9025/payload-test')
      .Accept('application/json')
      .AddBody(LPayload)
      .Post;

    // Deve falhar e retornar 413 Payload Too Large.
    // Como a funcionalidade não está implementada no core, o core vai processar e retornar 200,
    // fazendo o teste falhar no TDD (RED phase).
    Assert.AreEqual(413, LResponse.StatusCode);
  finally
    StopServer;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(THorseRequestTest);

end.
