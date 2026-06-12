# Diretrizes e Padronizações de Testes no Horse

Este documento estabelece as diretrizes arquiteturais e os padrões de codificação adotados na escrita de testes unitários e de integração para o núcleo do micro-framework **Horse**. O objetivo é garantir uma suíte de testes robusta, rápida e imune a falhas erráticas (como colisões de portas TCP e concorrência).

---

## 1. Princípios de Testes

Para manter a estabilidade da biblioteca em múltiplos compiladores (Delphi e FPC/Lazarus) e sistemas operacionais, a escrita de testes segue quatro pilares:

1. **Isolamento de Estado (State Isolation):** Nenhum caso de teste deve poluir ou depender do estado de outros testes.
2. **Ciclo de Vida Determinístico do Servidor:** A inicialização e parada do servidor HTTP devem ser sincronizadas, garantindo que o socket de rede esteja ativado antes de qualquer requisição do cliente.
3. **Isolamento de Portas (Port Isolation):** Uso de portas TCP variadas e altas para evitar conflitos com outros serviços locais e mitigar o tempo de espera do estado `TIME_WAIT` do sistema operacional.
4. **Isolamento de Testes Unitários vs. Integração:** Testes de componentes lógicos (como parsers de query/parâmetros) devem rodar 100% na RAM (sem rede). Testes de tráfego HTTP devem ser isolados em unidades integradas específicas.

---

## 2. Isolamento de Estado Global com `THorse.Reset`

O core do Horse utiliza um singleton estático global (`FRoutes` em [Horse.Core.pas](file:///C:/Users/weslley.capelari/Documents/Projetos/Github/weslleycapelari/horse/src/Horse.Core.pas)) que mantém a árvore de rotas e os middlewares ativos na memória do processo de testes.

### O Problema:
Se o Teste A registra a rota `/api/test`, e o Teste B tenta registrar a mesma rota (ou usa um setup similar), o barramento disparará uma exceção física `Duplicate route detected`, quebrando a execução concorrente.

### A Solução:
Para garantir que o estado de rotas e middlewares globais seja limpo após cada caso de teste, o core do Horse expõe a procedure estática `THorse.Reset`. 

Cada classe de teste que registre rotas **deve obrigatoriamente** invocar `THorse.Reset` na sua seção de `TearDown`:

```delphi
procedure THorseRequestTest.TearDown;
begin
  // Restaura configurações padrão e limpa a árvore global do Horse
  THorse.MaxPayloadSize := 10485760; 
  THorse.Reset; 
end;
```

O método `THorse.Reset` desaloca a árvore de roteamento e recria a lista de callbacks globais vazia, permitindo que cada teste subsequente registre livremente seus endpoints.

---

## 3. Diretrizes de Ciclo de Vida do Servidor em Testes Integrados

Ao escrever testes que sobem a escuta física do servidor HTTP, as seguintes diretrizes devem ser aplicadas:

### 3.1 Execução Assíncrona Não-Bloqueante
A chamada `THorse.Listen` é bloqueante por natureza. Para evitar travar a execução do runner DUnitX, o servidor deve ser iniciado em uma thread de background (thread anônima):

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
    TThread.Sleep(200); // Essencial para evitar race conditions
  end;
end;
```

### 3.2 Prevenção do Erro de Conexão Recusada (WinINet 12029)
Após dar o `.Start` na thread do servidor, o cliente HTTP de testes (como o `RESTRequest4D`) não deve disparar a requisição imediatamente. O Windows pode demorar milissegundos para agendar o socket físico e ativar a porta.
* **Padrão:** Sempre adicionar um delay mínimo (`TThread.Sleep(200)`) logo após iniciar a thread anônima do servidor para garantir que a porta física esteja ativa e ouvindo antes do request.

### 3.3 Uso de Portas TCP Altas e Variadas
Para evitar colisões com portas padrão ou serviços locais zumbis em background:
* **Não** utilize portas comumente usadas (como `80`, `443`, `8080`, `9000`).
* **Padrão:** Prefira portas altas entre `9010` e `9990` ou na faixa de `20000+` (ex: `9025` ou `28543`).

---

## 4. Estrutura Padrão de uma Unit de Teste de Integração (DUnitX)

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
  // As rotas de teste podem ser registradas no Setup porque o TearDown garante a limpeza do barramento
  RegisterRoutes;
end;

procedure THorseRequestTest.TearDown;
begin
  THorse.Reset; // Limpa o estado global para o próximo teste
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
    TThread.Sleep(200); // Aguarda ativação física do socket
  end;
end;

procedure THorseRequestTest.StopServer;
begin
  THorse.StopListen;
  TThread.Sleep(200); // Aguarda liberação do socket do Indy
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
