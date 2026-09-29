# stepMacro

Grava ações do jogador num arquivo texto e reproduz depois, em qualquer instância do OpenKore.

| Comando | Efeito |
|---|---|
| `stepmacro rec <nome>` | inicia a gravação |
| `stepmacro stoprec` | para e salva em `control/actions/<nome>.txt` |
| `stepmacro start <nome>` | reproduz o arquivo |
| `stepmacro stop` | aborta a reprodução |
| `atkid <nameID>` | ataca o monstro na tela com esse nameID (usado nos arquivos gravados, mas funciona direto no console também) |

## Por que isso observa principalmente as respostas do servidor (e uma coisa que não precisa mais)

No XKore 1 padrão, pacotes que o *cliente* manda pro servidor nunca passam pelo
processo do próprio OpenKore - só os pacotes que o OpenKore mesmo manda passam.
Então cliques reais no jogo são invisíveis do lado do envio, por padrão. O
plugin contorna isso observando as **respostas do servidor**, que sempre passam
pelo OpenKore, e inferindo a ação a partir delas:

- **Uso de item**: confirmação do servidor de uso de item (`packet_useitem`) ->
  `is <nome>`, só quando usado em si mesmo.
- **Adicionar ponto de atributo**: confirmação de mudança de status
  (`packet_charStats`) -> `stat_add str/agi/...`.
- **Adicionar ponto de skill**: pacote de level up de skill do servidor
  (`packet/skill_update`) -> `skills add <id>`. Falso positivo raro: esse
  pacote também pode disparar por outros motivos (ex.: skill compartilhada de
  grupo), não só por você mesmo gastar o ponto.
- **Conversa com NPC**: o próprio fluxo do diálogo (`npc_talk`, pedindo
  continuar/menu/número/texto, `npc_talk_done`) é visível, então `move <mapa>
  <x> <y>` + `talknpc <x> <y> <sequência>` é gravado automaticamente para as
  partes que não precisam de escolha (`c` = continuar). Qual item de menu,
  número ou texto você realmente mandou é um pacote cliente->servidor,
  invisível aqui por padrão - ver abaixo.
- **Mudança de configuração** (ex.: `lockMap`): sempre visível, seja pelo
  console ou pela GUI.
- **`buy`/`sell`/`store`**: só quando digitado no console/macro - clicar na
  janela da loja não é gravado (precisaria decodificar o protocolo de lista de
  itens da loja, fora de escopo por enquanto).

- **Ataque em monstro**: tanto o clique real (via `Network::clientSend/observed`,
  precisa da DLL - ver abaixo) quanto o comando digitado `a <#>` são gravados
  como `atkid <nameID>`, usando o ID da espécie do monstro (ex.: Poring = 1002),
  que é estável entre sessões - diferente do ID de instância, que muda a cada
  spawn. `atkid` é um comando novo, registrado por este plugin: na reprodução,
  ele procura na tela um monstro com esse nameID e ataca. Se nenhum estiver por
  perto no momento, dá erro e o `startaction` segue pra próxima linha.

Movimentação crua nunca é gravada.

### Menu/número/texto do NPC com precisão, usando o Kore-Bridge

Se você estiver usando a DLL injetada Kore-Bridge (`../Kore-Bridge` ao lado
deste repositório, ou qualquer DLL que fale o mesmo protocolo), ela agora
encaminha todo pacote que o *cliente* manda pro OpenKore como um frame `'C'` -
só observação, nunca reinjetado, então não pode causar uma ação duplicada.
`src/Network/XKore.pm` transforma isso no hook `Network::clientSend/observed`,
e este plugin usa isso **só** pra preencher a resposta/número/texto exatos do
NPC, substituindo o placeholder `r?`/`d?`/`t="?"` no momento em que o pacote
real é decodificado.

Isso precisa de:
1. Um build do Kore-Bridge com o frame `'C'` (ver o README dele).
2. `XKore 1` em `control/config.txt` (já é o padrão aqui).

Se o cliente embaralhar/XOR-ar os bytes de saída antes do `send()` (o README
do Kore-Bridge tem uma nota de troubleshooting sobre isso - o caminho de
injeção do `PacketService` sugere que pode), o opcode não vai bater com nada
na tabela do `$messageSender` e a decodificação é silenciosamente pulada -
você ainda fica com o placeholder, sem diferença de não ter a mudança na DLL.
Nada quebra de qualquer forma.

Formato do arquivo: um comando do OpenKore por linha, comentários com `#`.
Preencha qualquer placeholder `r?`/`d?`/`t="?"` restante antes de reproduzir,
ou copie o arquivo como está pra outra instância e edite lá.
