# Prioridades, SLA e OLA

Este documento descreve o que o [`install-glpi.sh`](servidor/install-glpi.sh) configura quando você responde **Sim** às perguntas:

```
Usar 4 níveis de prioridade (Baixa, Média, Alta, Muito alta) com a matriz ITIL? [S/n]:
Atrelar impacto à urgência (o chamado nasce com a prioridade escolhida pelo usuário)? [S/n]:
Criar SLAs e OLAs por prioridade e vincular automaticamente aos chamados? [S/n]:
Horário de atendimento de segunda a sexta (HH:MM-HH:MM) [08:00-18:00]:
A equipe atende aos sábados? [s/N]:
Cadastrar os feriados nacionais de data fixa no calendário? [S/n]:
```

---

## Prioridades: 4 níveis

O GLPI vem com 5 níveis de urgência e de impacto e 6 de prioridade. O instalador deixa só **4**:

| Nível | Urgência (quanto tempo pode esperar) | Impacto (quantos são afetados) |
|---|---|---|
| **Baixa** | pode esperar | uma pessoa, sem atrapalhar o trabalho |
| **Média** | atrapalha, mas dá para trabalhar | uma pessoa ou poucas |
| **Alta** | impede o trabalho | um setor ou um processo importante |
| **Muito alta** | precisa de solução imediata | a empresa toda ou um serviço crítico |

A **prioridade** é calculada sozinha pela matriz ITIL (urgência × impacto):

| Urgência ↓ / Impacto → | Baixo | Médio | Alto | Muito alto |
|---|---|---|---|---|
| **Baixa** | Baixa | Baixa | Média | Alta |
| **Média** | Baixa | Média | Alta | Alta |
| **Alta** | Média | Alta | Alta | Muito alta |
| **Muito alta** | Alta | Alta | **Muito alta** | **Muito alta** |

### Impacto atrelado à urgência

O usuário só informa a **urgência** ao abrir o chamado. Com a opção *Atrelar impacto à urgência*, o **impacto e a prioridade nascem iguais à urgência**: quem escolhe *Alta* recebe prioridade *Alta* e o SLA de *Alta*. Na matriz, isso corresponde à diagonal (Baixa/Baixo = Baixa, Alta/Alto = Alta etc.).

Depois que o chamado está aberto, o técnico pode ajustar, e **SLA e OLA sempre acompanham a nova prioridade**, para cima ou para baixo:

| O técnico altera | O que acontece |
|---|---|
| **Urgência** (ex.: Muito alta → Baixa) | impacto e prioridade acompanham a urgência; SLA e OLA viram os de *Baixa* |
| **Só o impacto** (ex.: urgência Média, impacto → Muito alto) | a urgência é mantida e a prioridade sai da matriz (*Alta*); SLA e OLA de *Alta* |
| **Só a prioridade** (ex.: Alta → Baixa) | SLA e OLA viram os de *Baixa*, e os prazos são recalculados |

> Na **abertura**, quem manda é a urgência: mesmo que o técnico já informe outra prioridade ao criar o chamado, ela é igualada à urgência. Para abrir com outra prioridade, ajuste a urgência ou altere a prioridade depois de criar.

Sem essa opção, o impacto fica em *Médio* na abertura. Aí, por exemplo, urgência *Muito alta* gera prioridade *Alta* até o técnico avaliar o impacto, que é o comportamento clássico do ITIL.

**Seletor manual de prioridade:** a tela do chamado do GLPI sempre lista também *Crítica* e *Muito baixa*. Se um técnico alterar o chamado para uma delas, as regras do instalador **corrigem automaticamente** para *Muito alta* e *Baixa*.

---

## SLA e OLA

| | Para quem é | Exemplo |
|---|---|---|
| **SLA** (acordo de nível de serviço) | o prazo prometido ao **usuário** | "problemas urgentes são resolvidos em até 4 horas" |
| **OLA** (acordo de nível operacional) | o prazo **interno** da equipe, mais curto que o SLA | "a equipe resolve em até 3 horas", com 1 hora de folga antes de estourar o SLA |

Cada um tem dois prazos: **1º atendimento** (alguém assume o chamado) e **solução**.

### Prazos criados

| Prioridade | SLA 1º atendimento | SLA solução | OLA 1º atendimento | OLA solução |
|---|---|---|---|---|
| **Muito alta** | 15 min | 4 h | 10 min | 3 h |
| **Alta** | 30 min | 8 h | 20 min | 6 h |
| **Média** | 2 h | 2 dias úteis | 1 h | 1 dia útil |
| **Baixa** | 4 h | 5 dias úteis | 3 h | 4 dias úteis |

Os prazos contam **só no horário de atendimento**. Um chamado *Alta* aberto na sexta às 16:00, com atendimento de seg a sex 08–18 e sáb 08–12, conta 2 h na sexta e 4 h no sábado, pula o domingo e o feriado de 12/10 e vence na **terça às 10:00**. Esse caso foi testado num GLPI real.

### Como fica no GLPI

| Item | Onde ver | O que o instalador cria |
|---|---|---|
| **Calendário** "Horário de atendimento" | Configurar › Listas suspensas › Calendários | seg a sex no horário informado, sábado (opcional) e feriados |
| **Feriados** | Configurar › Listas suspensas › Feriados | 9 feriados nacionais de data fixa, que se repetem todo ano |
| **SLM** "Níveis de serviço (ITIL)" | Configurar › Níveis de serviço | 8 SLAs e 8 OLAs (1º atendimento e solução para cada prioridade) |
| **Regras** "Prioridade pela urgência: ..." | Administração › Regras › Regras de negócio para chamados | 4 regras que igualam impacto e prioridade à urgência (rodam **antes** das de SLA) |
| **Regras** "SLA/OLA: prioridade ..." | Administração › Regras › Regras de negócio para chamados | 4 regras que aplicam SLA e OLA conforme a prioridade, **na abertura e a cada mudança** |

Feriados nacionais cadastrados: Confraternização Universal (01/01), Tiradentes (21/04), Dia do Trabalho (01/05), Independência (07/09), Nossa Senhora Aparecida (12/10), Finados (02/11), Proclamação da República (15/11), Consciência Negra (20/11) e Natal (25/12).

> **Feriados móveis** (Carnaval, Sexta-feira Santa, Corpus Christi) e **feriados estaduais ou municipais** mudam a cada ano ou cidade. Cadastre-os em **Feriados** e vincule ao calendário "Horário de atendimento".

### O que acontece num chamado

1. O chamado é aberto. A prioridade é calculada pela matriz, a regra correspondente aplica o **SLA** e a **OLA**, e o GLPI calcula os prazos.
2. Na lista de chamados e no próprio chamado aparecem **"Tempo para atribuição"** e **"Tempo para solução"**, com o prazo de cada um.
3. Se a prioridade mudar (por exemplo, o técnico aumenta o impacto), a regra **troca o SLA e a OLA** e os prazos são recalculados.

---

## Personalizar

- **Depois de instalar:** altere os prazos em **Configurar › Níveis de serviço**, o horário em **Calendários** e os feriados em **Feriados**.
- **Escalonamento:** em cada SLA e OLA, a aba **Níveis de escalonamento** permite, por exemplo, notificar o gestor quando faltar 1 hora para vencer, ou reatribuir o chamado.
- **Antes de instalar** (para usar outros prazos em várias empresas): edite a função `sla_catalog` no `install-glpi.sh`. Cada linha segue o formato:
  ```
  prioridade|nome|SLA 1º atendimento|SLA solução|OLA 1º atendimento|OLA solução
  5|Muito alta|15m|4h|10m|3h
  ```
  Use `m` para minutos, `h` para horas e `d` para dias úteis.

---

## Testes

Validado num GLPI 11 real, com chamados criados pela API:

| Cenário | Resultado |
|---|---|
| Urgência × impacto para cada prioridade | prioridade conforme a matriz ✅ |
| Usuário abre com urgência Alta (impacto não informado) | impacto e prioridade **Alta**, SLA de Alta ✅ |
| Técnico muda só o impacto (urgência Média, impacto Muito alto) | prioridade **Alta** pela matriz, urgência mantida ✅ |
| Prazos com sábado, domingo e feriado no meio | calculados conforme o calendário ✅ |
| Técnico **rebaixa** a prioridade (Alta → Baixa) | SLA e OLA trocados para Baixa e prazo recalculado ✅ |
| Técnico reduz a urgência (Muito alta → Baixa) | impacto, prioridade, SLA e OLA vão para Baixa ✅ |
| Chamado muda de Baixa para Muito alta | SLA e OLA trocados e prazo recalculado ✅ |
| Técnico altera para *Crítica* ou *Muito baixa* | corrigido para *Muito alta* / *Baixa*, com o SLA certo ✅ |
