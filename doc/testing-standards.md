# Testing Guidelines and Standards in Horse

This document establishes the architectural guidelines and coding standards adopted for writing unit and integration tests for the **Horse** micro-framework core. The objective is to guarantee a robust, fast, and flake-free test suite (immune to TCP port collisions and concurrency issues).

---

## 1. Testing Principles

To maintain library stability across multiple compilers (Delphi and FPC/Lazarus) and operating systems, test writing follows four core pillars:

1. **State Isolation:** No test case should pollute or depend on the state of other tests.
2. **Deterministic Server Lifecycle:** Server HTTP startup and shutdown must be synchronized, ensuring the physical socket is active before any client requests are dispatched.
3. **Port Isolation:** Use of high, varied TCP ports to avoid conflicts with other local services and mitigate operating system `TIME_WAIT` states.
4. **Separation of Unit vs. Integration Tests:** Logic-only components (such as query/parameter parsers) should run 100% in RAM (no network). HTTP traffic tests should be isolated in dedicated integration test classes.

---

## 2. Global State Isolation with `THorse.Reset`

The Horse core uses a global static singleton (`FRoutes` in [Horse.Core.pas](../src/Horse.Core.pas)) that stores the route tree and active global middlewares in memory throughout the test runner process.

### The Problem

If Test A registers `/api/test`, and Test B attempts to register the same route (or uses a similar setup), the core will throw a physical `Duplicate route detected` exception, breaking concurrent test execution.

### The Solution

To ensure the route tree and global middleware state is wiped clean after each test case, the Horse core exposes the static method `THorse.Reset`.

Every test class that registers routes **must** invoke `THorse.Reset` inside its `TearDown` section:

```delphi
procedure THorseRequestTest.TearDown;
begin
  // Restores default configs and clears the global Horse routing tree
  THorse.MaxPayloadSize := 10485760; 
  THorse.Reset; 
end;
```

The `THorse.Reset` method deallocates the routing tree and recreates an empty global callback list, allowing subsequent tests to register routes cleanly.

---

## 3. Server Lifecycle Guidelines in Integration Tests

When writing tests that spin up a physical HTTP listener, the following guidelines apply:

### 3.1 Non-Blocking Asynchronous Execution

The `THorse.Listen` method is blocking by default. To avoid hanging the DUnitX runner, the server must be spawned on a background thread (anonymous thread):

```delphi
procedure TApiTest.StartApiListen;
begin
  if (not THorse.IsRunning) then
  begin
    TThread.CreateAnonymousThread(
      procedure
      begin
        THorse.Listen(9025);
      end).Start;
    TThread.Sleep(200); // Essential to avoid race conditions
  end;
end;
```

### 3.2 Connection Refused Prevention (WinINet 12029)

After calling `.Start` on the server thread, the client HTTP library (e.g. `RESTRequest4D`) must not send the request immediately. The OS can take some milliseconds to bind the socket.

* **Standard:** Always inject a minimum delay (`TThread.Sleep(200)`) right after starting the server thread to ensure the socket is active and listening before dispatching requests.

### 3.3 High and Varied TCP Ports

To avoid collisions with standard ports or background zombie services:

* **Do not** use commonly occupied ports (such as `80`, `443`, `8080`, `9000`).
* **Standard:** Use high ports in the range `9010` to `9990` or `20000+` (e.g., `9025` or `28543`).

---

## 4. Standard Integration Test Unit Structure (DUnitX)

```delphi
unit Tests.Horse.Request;

interface

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
  end;

implementation

procedure THorseRequestTest.Setup;
begin
  // Route mapping can be registered in Setup because TearDown guarantees global state cleanup
  RegisterRoutes;
end;

procedure THorseRequestTest.TearDown;
begin
  THorse.Reset; // Clears global state for the next test
end;

procedure THorseRequestTest.RegisterRoutes;
begin
  THorse.Post('/payload-test',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      Res.Send('{"status": "ok"}').Status(THTTPStatus.Ok);
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
    TThread.Sleep(200); // Wait for the physical socket to bind
  end;
end;

procedure THorseRequestTest.StopServer;
begin
  THorse.StopListen;
  TThread.Sleep(200); // Wait for the socket to be released
end;

procedure THorseRequestTest.TestPayloadWithinLimit;
var
  LResponse: IResponse;
begin
  StartServer;
  try
    LResponse := TRequest.New.BaseURL('http://localhost:9025/payload-test').Post;
    Assert.AreEqual(200, LResponse.StatusCode);
  finally
    StopServer;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(THorseRequestTest);

end.
```
