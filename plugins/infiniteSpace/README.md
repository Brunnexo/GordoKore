# infiniteSpace

Automatiza Espaço Infinito (`1@infi`) desde dentro del mapa. No crea la instancia ni habla con la Arqueóloga de afuera.

Automatiza o Espaço Infinito (`1@infi`) a partir de dentro do mapa. Não cria a instância nem fala com a Arqueóloga de fora.

Archivos / Arquivos:

- `infiniteSpace.pl` — plugin
- `Route.pm` — ruta fija de las 50 salas / rota fixa das 50 salas

Los textos de consola y del registro salen en los dos idiomas: `español | português`.

Os textos do console e do registro saem nos dois idiomas: `espanhol | português`.

---

## Español

### Qué hace

1. El personaje entra a Espaço Infinito a mano y queda en la primera sala (entrada `30,10`).
2. El plugin elige Modo Difícil en el NPC `42,8`.
3. Limpia las 50 salas.
4. Abre los 5 cofres de MVP.
5. Sale hablando con la Arqueóloga en `366,392`.

Si el bot entra con la instancia ya empezada, deduce la sala por las coordenadas y retoma desde ahí.

No parchea el núcleo de OpenKore. No escribe `config.txt`, `pickupitems.txt` ni `tables/ROla/portals.txt`.

### Instalación

El plugin y `Route.pm` tienen que estar en la misma carpeta. En `control/sys.txt`, dentro de `loadPlugins_list`, agregar `infiniteSpace`.

También se puede cargar en caliente:

```
plugin load infiniteSpace
plugin reload infiniteSpace
```

Se activa solo cuando el mapa base es `1@infi`. En cualquier otro mapa no hace nada.

### Uso

1. Crear y entrar a Espaço Infinito manualmente.
2. Dejar al personaje en la primera sala, o en cualquier sala si la corrida ya empezó.
3. Iniciar OpenKore con cualquier perfil, o recargar el plugin si ya está adentro.
4. La primera corrida real tiene que ser supervisada. `infi off` si una sala, un cofre o un portal no se comporta como se espera.

### Comandos

| Comando | Efecto |
|---|---|
| `infi status` | Estado, sala, posición, MVP, cofre, mobs, acompañantes, fantasmas y si la config temporal está activa |
| `infi off` | Detiene la automatización, deja la IA en manual y restaura el perfil |
| `infi on` | Vuelve a habilitarla. Si está dentro, retoma desde la posición |
| `infi reset` | Olvida la sala y la vuelve a deducir desde las coordenadas |

El registro queda en `instancias/infiniteSpace.log`, relativo a la carpeta de OpenKore.

### Configuración opcional

Solo hace falta agregarla al `config.txt` del perfil si se quiere cambiar un valor. Los predeterminados son Modo Difícil y salida automática.

```
infiniteSpace_enabled 1
infiniteSpace_difficulty hard
infiniteSpace_exit 1
infiniteSpace_roomTimeout 900
infiniteSpace_actionTimeout 20
infiniteSpace_portalSweepDelay 12
infiniteSpace_chestDelay 8
infiniteSpace_weight 90
infiniteSpace_dryRun 0
```

| Clave | Predeterminado | Significado |
|---|---|---|
| `infiniteSpace_enabled` | 1 | 0 desactiva el plugin |
| `infiniteSpace_difficulty` | hard | `hard` elige Modo Difícil. `easy` elige Modo Fácil |
| `infiniteSpace_exit` | 1 | 1 sale con la Arqueóloga después del quinto cofre. 0 se queda dentro |
| `infiniteSpace_roomTimeout` | 900 | Segundos máximos por sala. Al pasarse, se detiene |
| `infiniteSpace_actionTimeout` | 20 | Segundos para reintentar un clic o una ruta que no llegó |
| `infiniteSpace_portalSweepDelay` | 12 | Segundos quieto en la coordenada del portal antes de recorrer toda la sala |
| `infiniteSpace_chestDelay` | 8 | Segundos junto al cofre antes de pulsarlo |
| `infiniteSpace_weight` | 90 | Porcentaje de peso que detiene la corrida |
| `infiniteSpace_dryRun` | 0 | 1 anuncia las acciones y no mueve ni habla |
| `infiniteSpace_set_<clave>` | | Pisa o agrega una clave de la config temporal. Ejemplo: `infiniteSpace_set_attackDistance 1` |

Para pisar una clave solo mientras dura la instancia:

```
infiniteSpace_set_attackDistance 1
```

### No hace falta editar el perfil

Al entrar a `1@infi` el plugin copia los valores originales, los pisa en memoria y guarda la copia en `instancias/estado/<perfil>.config_previo.txt`. Al salir, al detenerse, al morir o al desconectarse, restaura cada valor y borra la copia.

OpenKore, al guardar la config, escribiría el archivo del perfil con los valores temporales. Si eso ocurre durante la instancia, el archivo se reescribe con los valores originales. Los temporales se vuelven a aplicar solo en memoria.

En memoria, mientras está dentro:

- `lockMap 1@infi`, `route_randomWalk 0`, storage, sell y buy apagados.
- `attackAuto` al menos 2, `attackMaxDistance` al menos 2, `attackRouteMaxPathDistance` al menos 20, `attackMaxRouteTime` al menos 6. Si el perfil ya tiene un número mayor, se respeta.
- `attackAuto_inLockOnly 0`, `attackAuto_onlyWhenSafe 0`, `attackChangeTarget 0`, `attackNoGiveup 1`.
- Los `teleportAuto_*` que sacan al personaje del mapa quedan en 0: HP, SP, portal, idle, search, dropTarget, lostTarget, unstuck, deadly, daño, agresivos, fallos y uso de skill de teletransporte.
- `route_escape_reachedNoPortal 0`, `route_escape_randomWalk 0`.
- `portalRecord 0` y `portalRecord_recompileAfter 0`, para no guardar los portales de la instancia.

`mon_control.txt` no se toca. Un perfil que solo ataca un mob (por ejemplo `all -1` y solo el Polluted Wanderer) igual limpia la instancia: el plugin ordena el ataque directo. Fuera de `1@infi` el perfil vuelve a su regla.

### Pickup

Al entrar reemplaza `%pickupitems` en memoria: `all 0` y prioridad 2 solo para estos ID. Al salir restaura el hash original. No escribe `pickupitems.txt`.

```
6905, 968, 18128, 28703, 603, 607, 730, 1000, 1029,
4642, 4643, 4644, 4645, 4647, 4648, 4649, 4650, 4651,
4121, 4123, 4131, 4132, 4134, 4135, 4137, 4140, 4142, 4143,
4144, 4146, 4147, 4168, 4189, 4263, 4276, 4302, 4305, 4318, 4324
```

`6905` es el Pó Espacial. Si uno de esos ítems está en el piso a 30 celdas o menos, el plugin lo recoge antes que la ruta, el MVP o el camino al cofre. Cada ítem se intenta 4 veces. No interrumpe el diálogo del cofre, el de la Arqueóloga ni el del NPC inicial. El Poring de Ouro va primero.

### Ruta

Cinco bloques de 10 salas. Cada sala tiene entrada y portal de salida. La última de cada bloque es de MVP y tiene cofre.

| Bloque | Pasillo X | Cofre |
|---|---|---|
| 1 | 30 | 30,369 |
| 2 | 112 | 112,369 |
| 3 | 198 y luego 194 | 194,380 |
| 4 | 280 | 280,380 |
| 5 | 362 y luego 366 | 366,380 |

La Arqueóloga de salida está en `366,392`.

La sala no se elige por la entrada más cercana: la entrada de la sala siguiente puede quedar más cerca en coordenadas y del otro lado del muro. Primero se usa la franja de Y entre la entrada y el portal, con el X a 40 celdas o menos.

Salas grandes, confirmadas en juego: 4, 10, 15, 20, 25, 29, 35, 40, 45 y 50.

### Cómo recorre cada sala

1. Mata lo que ve. El Poring de Ouro (Poring de Ouro, Golden Poring, Gold Poring o Poring Dourado) corta cualquier otra acción y se lo persigue hasta matarlo.
2. No pisa el portal mientras quede un mob. La sala tiene que verse vacía 3 segundos y el portal tiene que estar en la coordenada esperada.
3. Hasta entonces solo camina el pasillo: el medio de la sala y un punto a 4 celdas del portal. También en las salas de MVP, donde el jefe está cerca del final.
4. Si el personaje lleva 12 segundos (`infiniteSpace_portalSweepDelay`) a 2 celdas o menos del portal y no cruza, recorre toda la sala. En sala grande la grilla es de ±40 celdas con un punto cada 5. En las demás, ±18 con un punto cada 8. Solo usa celdas caminables y con camino, para no intentar cruzar el muro.
5. Si durante el recorrido aparece un mob, lo caza. El recorrido se cancela. Si el portal sigue cerrado, hay que volver a la coordenada y esperar otros 12 segundos. A los 6 intentos sin cruzar, se detiene.
6. Si OpenKore suelta un mob por línea de visión o por no poder llegar, el plugin camina hasta él y lo vuelve a atacar.

Un actor que cruzó el portal junto con el personaje se trata como acompañante, no como mob de la sala nueva. También se ignora a quien se persigue 25 segundos, sigue a 3 celdas o menos y nunca intercambió daño.

Al morir el MVP, el servidor borra a sus esclavos sin avisar y OpenKore los deja en la lista. El plugin los quita si el nombre coincide con `escrav`. Un Megalith quieto sigue contando como mob y hay que matarlo.

### Cofres y salida

En sala de jefe, al morir el MVP el plugin espera el cofre. Si ese aviso no llegó, un portal abierto con la sala vacía 5 segundos se toma como MVP ya muerto.

El cofre se pulsa cuando el NPC está en su coordenada, el personaje está a 2 celdas o menos y pasaron 8 segundos (`infiniteSpace_chestDelay`). El portal no cancela ese diálogo. Recién cuando la conversación terminó sigue al portal. En la sala 50 habla con la Arqueóloga, salvo que `infiniteSpace_exit` sea 0.

El menú inicial acepta `Difícil` y `Dificil`. Con `infiniteSpace_difficulty easy` busca `Fácil`.

### Cuándo se detiene

Deja la IA en manual si el personaje muere, si el peso llega al límite, si una sala supera el tiempo, si sale de `1@infi` fuera de la secuencia final, si el NPC inicial, el cofre o la Arqueóloga fallan 3 veces, o si el portal falla 6 veces.

---

## Português

### O que faz

1. O personagem entra no Espaço Infinito na mão e fica na primeira sala (entrada `30,10`).
2. O plugin escolhe Modo Difícil no NPC `42,8`.
3. Limpa as 50 salas.
4. Abre os 5 baús de MVP.
5. Sai falando com a Arqueóloga em `366,392`.

Se o bot entrar com a instância já começada, deduz a sala pelas coordenadas e retoma dali.

Não altera o núcleo do OpenKore. Não escreve `config.txt`, `pickupitems.txt` nem `tables/ROla/portals.txt`.

### Instalação

O plugin e o `Route.pm` precisam estar na mesma pasta. Em `control/sys.txt`, dentro de `loadPlugins_list`, adicionar `infiniteSpace`.

Também dá para carregar em quente:

```
plugin load infiniteSpace
plugin reload infiniteSpace
```

Só ativa quando o mapa base é `1@infi`. Em qualquer outro mapa não faz nada.

### Uso

1. Criar e entrar no Espaço Infinito manualmente.
2. Deixar o personagem na primeira sala, ou em qualquer sala se a corrida já começou.
3. Iniciar o OpenKore com qualquer perfil, ou recarregar o plugin se já estiver dentro.
4. A primeira corrida real tem que ser supervisionada. `infi off` se uma sala, um baú ou um portal não se comportar como o esperado.

### Comandos

| Comando | Efeito |
|---|---|
| `infi status` | Estado, sala, posição, MVP, baú, mobs, acompanhantes, fantasmas e se a config temporária está ativa |
| `infi off` | Para a automação, deixa a IA em manual e restaura o perfil |
| `infi on` | Volta a habilitar. Se estiver dentro, retoma da posição |
| `infi reset` | Esquece a sala e a deduz de novo pelas coordenadas |

O registro fica em `instancias/infiniteSpace.log`, relativo à pasta do OpenKore.

### Configuração opcional

Só é preciso colocar no `config.txt` do perfil se quiser mudar um valor. O padrão é Modo Difícil e saída automática.

```
infiniteSpace_enabled 1
infiniteSpace_difficulty hard
infiniteSpace_exit 1
infiniteSpace_roomTimeout 900
infiniteSpace_actionTimeout 20
infiniteSpace_portalSweepDelay 12
infiniteSpace_chestDelay 8
infiniteSpace_weight 90
infiniteSpace_dryRun 0
```

| Chave | Padrão | Significado |
|---|---|---|
| `infiniteSpace_enabled` | 1 | 0 desativa o plugin |
| `infiniteSpace_difficulty` | hard | `hard` escolhe Modo Difícil. `easy` escolhe Modo Fácil |
| `infiniteSpace_exit` | 1 | 1 sai com a Arqueóloga depois do quinto baú. 0 fica dentro |
| `infiniteSpace_roomTimeout` | 900 | Segundos máximos por sala. Ao passar, para |
| `infiniteSpace_actionTimeout` | 20 | Segundos para tentar de novo um clique ou uma rota que não chegou |
| `infiniteSpace_portalSweepDelay` | 12 | Segundos parado na coordenada do portal antes de varrer a sala inteira |
| `infiniteSpace_chestDelay` | 8 | Segundos junto ao baú antes de clicá-lo |
| `infiniteSpace_weight` | 90 | Porcentagem de peso que para a corrida |
| `infiniteSpace_dryRun` | 0 | 1 anuncia as ações e não move nem fala |
| `infiniteSpace_set_<clave>` | | Substitui ou adiciona uma chave da config temporária. Exemplo: `infiniteSpace_set_attackDistance 1` |

Para substituir uma chave só enquanto a instância durar:

```
infiniteSpace_set_attackDistance 1
```

### Não é preciso editar o perfil

Ao entrar em `1@infi` o plugin copia os valores originais, substitui em memória e guarda a cópia em `instancias/estado/<perfil>.config_previo.txt`. Ao sair, parar, morrer ou desconectar, restaura cada valor e apaga a cópia.

O OpenKore, ao salvar a config, escreveria o arquivo do perfil com os valores temporários. Se isso acontecer durante a instância, o arquivo é reescrito com os valores originais. Os temporários voltam a valer só em memória.

Em memória, enquanto estiver dentro:

- `lockMap 1@infi`, `route_randomWalk 0`, storage, sell e buy desligados.
- `attackAuto` no mínimo 2, `attackMaxDistance` no mínimo 2, `attackRouteMaxPathDistance` no mínimo 20, `attackMaxRouteTime` no mínimo 6. Se o perfil já tiver um número maior, ele é mantido.
- `attackAuto_inLockOnly 0`, `attackAuto_onlyWhenSafe 0`, `attackChangeTarget 0`, `attackNoGiveup 1`.
- Os `teleportAuto_*` que tiram o personagem do mapa ficam em 0: HP, SP, portal, idle, search, dropTarget, lostTarget, unstuck, deadly, dano, agressivos, erros e uso de skill de teleporte.
- `route_escape_reachedNoPortal 0`, `route_escape_randomWalk 0`.
- `portalRecord 0` e `portalRecord_recompileAfter 0`, para não gravar os portais da instância.

O `mon_control.txt` não é alterado. Um perfil que só ataca um mob (por exemplo `all -1` e só o Polluted Wanderer) mesmo assim limpa a instância: o plugin manda o ataque direto. Fora de `1@infi` o perfil volta à regra dele.

### Pickup

Ao entrar substitui `%pickupitems` em memória: `all 0` e prioridade 2 só para estes IDs. Ao sair restaura o hash original. Não escreve `pickupitems.txt`.

```
6905, 968, 18128, 28703, 603, 607, 730, 1000, 1029,
4642, 4643, 4644, 4645, 4647, 4648, 4649, 4650, 4651,
4121, 4123, 4131, 4132, 4134, 4135, 4137, 4140, 4142, 4143,
4144, 4146, 4147, 4168, 4189, 4263, 4276, 4302, 4305, 4318, 4324
```

`6905` é o Pó Espacial. Se um desses itens estiver no chão a 30 células ou menos, o plugin recolhe antes da rota, do MVP ou do caminho até o baú. Cada item é tentado 4 vezes. Não interrompe o diálogo do baú, o da Arqueóloga nem o do NPC inicial. O Poring de Ouro vem primeiro.

### Rota

Cinco blocos de 10 salas. Cada sala tem entrada e portal de saída. A última de cada bloco é de MVP e tem baú.

| Bloco | Corredor X | Baú |
|---|---|---|
| 1 | 30 | 30,369 |
| 2 | 112 | 112,369 |
| 3 | 198 e depois 194 | 194,380 |
| 4 | 280 | 280,380 |
| 5 | 362 e depois 366 | 366,380 |

A Arqueóloga de saída está em `366,392`.

A sala não é escolhida pela entrada mais próxima: a entrada da sala seguinte pode ficar mais perto em coordenadas e do outro lado do muro. Primeiro se usa a faixa de Y entre a entrada e o portal, com o X a 40 células ou menos.

Salas grandes, confirmadas em jogo: 4, 10, 15, 20, 25, 29, 35, 40, 45 e 50.

### Como percorre cada sala

1. Mata o que vê. O Poring de Ouro (Poring de Ouro, Golden Poring, Gold Poring ou Poring Dourado) corta qualquer outra ação e é perseguido até morrer.
2. Não pisa no portal enquanto houver um mob. A sala tem que parecer vazia por 3 segundos e o portal tem que estar na coordenada esperada.
3. Até lá só caminha o corredor: o meio da sala e um ponto a 4 células do portal. Também nas salas de MVP, onde o chefe está perto do final.
4. Se o personagem ficar 12 segundos (`infiniteSpace_portalSweepDelay`) a 2 células ou menos do portal e não cruzar, varre a sala inteira. Em sala grande a grade é de ±40 células com um ponto a cada 5. Nas outras, ±18 com um ponto a cada 8. Só usa células andáveis e com caminho, para não tentar atravessar o muro.
5. Se durante a varredura aparecer um mob, ele é caçado. A varredura é cancelada. Se o portal continuar fechado, é preciso voltar à coordenada e esperar outros 12 segundos. Aos 6 tentativas sem cruzar, para.
6. Se o OpenKore soltar um mob por linha de visão ou por não conseguir chegar, o plugin caminha até ele e ataca de novo.

Um ator que cruzou o portal junto com o personagem é tratado como acompanhante, não como mob da sala nova. Também é ignorado quem é perseguido por 25 segundos, continua a 3 células ou menos e nunca trocou dano.

Ao morrer o MVP, o servidor apaga os escravos sem avisar e o OpenKore os deixa na lista. O plugin os remove se o nome coincidir com `escrav`. Um Megalith parado continua contando como mob e tem que ser morto.

### Baús e saída

Na sala de chefe, ao morrer o MVP o plugin espera o baú. Se esse aviso não chegou, um portal aberto com a sala vazia por 5 segundos é tratado como MVP já morto.

O baú é clicado quando o NPC está na coordenada, o personagem está a 2 células ou menos e passaram 8 segundos (`infiniteSpace_chestDelay`). O portal não cancela esse diálogo. Só quando a conversa terminou segue para o portal. Na sala 50 fala com a Arqueóloga, salvo se `infiniteSpace_exit` for 0.

O menu inicial aceita `Difícil` e `Dificil`. Com `infiniteSpace_difficulty easy` procura `Fácil`.

### Quando para

Deixa a IA em manual se o personagem morrer, se o peso chegar ao limite, se uma sala passar do tempo, se sair de `1@infi` fora da sequência final, se o NPC inicial, o baú ou a Arqueóloga falharem 3 vezes, ou se o portal falhar 6 vezes.
