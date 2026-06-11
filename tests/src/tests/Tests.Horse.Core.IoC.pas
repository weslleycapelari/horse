unit Tests.Horse.Core.IoC;

interface

{$IF DEFINED(FPC)}
  {$MODE DELPHI}{$H+}
{$ENDIF}

uses
  DUnitX.TestFramework, Horse, Horse.Commons, Horse.Request, Horse.Response,
  System.SysUtils, System.Classes, System.JSON, RESTRequest4D.Request;

type
  // Mock do controller de teste
  TTestController = class
  public
    class var FInstanceCount: Integer;
    class var FReleaseCount: Integer;
    class var FActionCalled: Boolean;

    constructor Create;
    destructor Destroy; override;
    procedure DoGetAction(Req: THorseRequest; Res: THorseResponse);
  end;

  // Mock do resolver de dependência
  TTestDependencyResolver = class(TInterfacedObject, IHorseDependencyResolver)
  public
    function GetService(AClass: TClass): TObject;
    procedure Release(AService: TObject);
  end;

  [TestFixture]
  THorseIoCTest = class(TObject)
  private
    FResolver: IHorseDependencyResolver;
    procedure StartServer;
    procedure StopServer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestRegisterResolver;

    [Test]
    procedure TestResolveAndExecuteAction;
  end;

implementation

{ TTestController }

constructor TTestController.Create;
begin
  Inc(FInstanceCount);
  FActionCalled := False;
end;

destructor TTestController.Destroy;
begin
  inherited;
end;

procedure TTestController.DoGetAction(Req: THorseRequest; Res: THorseResponse);
begin
  FActionCalled := True;
  Res.Send('{"status": "ok"}').Status(THTTPStatus.Ok);
end;

{ TTestDependencyResolver }

function TTestDependencyResolver.GetService(AClass: TClass): TObject;
begin
  if AClass = TTestController then
    Result := TTestController.Create
  else
    Result := nil;
end;

procedure TTestDependencyResolver.Release(AService: TObject);
begin
  if AService is TTestController then
  begin
    Inc(TTestController.FReleaseCount);
    AService.Free;
  end;
end;

{ THorseIoCTest }

procedure THorseIoCTest.Setup;
begin
  TTestController.FInstanceCount := 0;
  TTestController.FReleaseCount := 0;
  TTestController.FActionCalled := False;
  FResolver := TTestDependencyResolver.Create;
end;

procedure THorseIoCTest.TearDown;
begin
  FResolver := nil;
  THorse.DependencyResolver := nil;
end;

procedure THorseIoCTest.StartServer;
begin
  if not THorse.IsRunning then
  begin
    TThread.CreateAnonymousThread(
      procedure
      begin
        THorse.Listen(9001);
      end).Start;
    TThread.Sleep(200); // Aguarda inicialização do servidor
  end;
end;

procedure THorseIoCTest.StopServer;
begin
  THorse.StopListen;
  TThread.Sleep(200); // Aguarda parada do servidor
end;

procedure THorseIoCTest.TestRegisterResolver;
begin
  THorse.DependencyResolver := FResolver;
  Assert.AreSame(FResolver, THorse.DependencyResolver);
end;

procedure THorseIoCTest.TestResolveAndExecuteAction;
var
  LResponse: IResponse;
begin
  THorse.DependencyResolver := FResolver;

  // Registra a rota usando a classe do controller e o método
  THorse.Get('/ioc-test', TTestController, 'DoGetAction');

  StartServer;
  try
    LResponse := TRequest.New.BaseURL('http://localhost:9001/ioc-test')
      .Accept('application/json')
      .Get;

    Assert.AreEqual(200, LResponse.StatusCode);
    Assert.IsTrue(TTestController.FActionCalled, 'Action method should have been called');
    Assert.AreEqual(1, TTestController.FInstanceCount, 'Controller instance should have been resolved once');
    Assert.AreEqual(1, TTestController.FReleaseCount, 'Controller instance should have been released once');
  finally
    StopServer;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(THorseIoCTest);

end.
