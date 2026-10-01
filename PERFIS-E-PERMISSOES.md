# Perfis, grupos e permissões

Este documento descreve o que o [`install-glpi.sh`](servidor/install-glpi.sh) cria quando você responde **Sim** à pergunta:

```
Criar grupos de atendimento por área e perfis de acesso (cada área vê só os seus chamados)? [S/n]:
Outras equipes/departamentos que abrem chamados, separados por vírgula (Enter = nenhum):
```

**Resumo:** cada área atende e enxerga **só os seus chamados**, os gestores acompanham a própria equipe, os colaboradores veem os chamados deles, e **só o Super-Admin vê tudo**.

---

## Como funciona

No GLPI, o acesso de cada pessoa depende de duas coisas:

| | Define | Exemplo |
|---|---|---|
| **Perfil** | **o que** a pessoa pode fazer | atender chamados, ver estatísticas, ver o inventário |
| **Grupo** | **quais** chamados ela enxerga | grupo RH: chamados do RH |

Por isso não existe um perfil por área. **"Atendente de Área" + grupo RH** é o atendente do RH, e **"Atendente de Área" + grupo Financeiro** é o atendente do Financeiro.

Dois automatismos fazem tudo funcionar sem triagem manual:

1. **Atribuição pela categoria:** cada categoria tem o grupo da sua área como responsável. Um chamado aberto em *RH › Benefícios › Vale-transporte* cai direto no grupo **RH**.
2. **Grupo do requerente:** uma regra por grupo marca, no chamado, o grupo de quem o abriu. Um chamado aberto por alguém da equipe **Comercial** fica com "Comercial" como grupo requerente, e é assim que o gestor do Comercial consegue enxergá-lo. A regra usa os grupos de que a pessoa **faz parte**, sem precisar preencher mais nada no cadastro.

---

## Perfis criados

| Perfil | Interface | Vê quais chamados | Pode |
|---|---|---|---|
| **Super-Admin** *(já existe)* | padrão | **todos** | tudo. Use só para o administrador do sistema |
| **Técnico de TI** | padrão | atribuídos a ele ou ao grupo TI, e os que ele abriu | atender, assumir chamados, mudar prioridade, **inventário completo** (computadores, rede, softwares...) |
| **Gestor de TI** | padrão | o do técnico de TI **+ abertos pela equipe TI** | o do técnico + **atribuir** chamados a outras pessoas, estatísticas e relatórios |
| **Atendente de Área** | padrão | atribuídos a ele ou ao grupo da área, e os que ele abriu | atender, assumir chamados, mudar prioridade. **Sem acesso ao inventário** |
| **Gestor de Área** | padrão | o do atendente **+ abertos pela equipe da área** | o do atendente + **atribuir** chamados, aprovar solicitações, estatísticas e relatórios |
| **Gestor de Equipe** | simplificada | os dele, os que observa **+ abertos pela sua equipe** | abrir e acompanhar chamados. Para gestores de setores que não atendem (ex.: Comercial) |
| **Self-Service** *(já existe)* | simplificada | os dele e os que observa | abrir e acompanhar chamados. Perfil padrão dos colaboradores |

Nenhum perfil novo tem **"Ver todos os chamados"** nem **"Ver chamados novos"**. Essa última mostraria os chamados recém-abertos de qualquer área, por exemplo um chamado de RH para a TI.

> Os perfis de TI só são criados quando a área **TI** é escolhida.

---

## Grupos criados

| Grupo | Atende chamados | Abre chamados | Origem |
|---|---|---|---|
| TI, RH, Financeiro, Marketing | ✅ | ✅ | áreas escolhidas na instalação |
| Ex.: Jurídico, Compras, Facilities | ✅ | ✅ | "outros departamentos que atendem" informados na instalação |
| Ex.: Comercial, Produção, Logística | — | ✅ | "outras equipes" informadas na instalação |

Todos os grupos ficam na matriz e valem para todas as filiais.

---

## Como liberar o acesso de uma pessoa

Em **Administração › Usuários**, abra o usuário e:

1. Na aba **Habilitações**, adicione o **perfil** na entidade da matriz, com **Recursivo = Sim**.
2. Na aba **Grupos**, adicione o **grupo** da pessoa. Para gestores, marque **Gerente** (opcional, usado nas aprovações).
3. Remova o perfil Self-Service se a pessoa for **só** atendente. Se ela também abre chamados como colaboradora, pode manter os dois e alternar o perfil no canto superior direito.

| Quem | Perfil | Grupo |
|---|---|---|
| Atendente do RH | Atendente de Área | RH |
| Gestor(a) do RH | Gestor de Área | RH |
| Analista do Financeiro | Atendente de Área | Financeiro |
| Técnico(a) de TI | Técnico de TI | TI |
| Coordenador(a) de TI | Gestor de TI | TI |
| Gestor(a) do Comercial | Gestor de Equipe | Comercial |
| Vendedor(a) | Self-Service | Comercial |
| Administrador do sistema | Super-Admin | — |

> **Todo colaborador deve estar no grupo da sua equipe.** Sem isso, o chamado dele não aparece para o gestor da equipe. Com **AD/LDAP ou SSO**, grupos e perfis podem ser preenchidos automaticamente. Veja o passo a passo em **[INTEGRACAO-LDAP-SSO.md](INTEGRACAO-LDAP-SSO.md)**.

### Restringir a uma filial

Para um atendente que só deve ver os chamados de uma filial, adicione o perfil **na entidade da filial**, e não na matriz. Ele vai enxergar somente os chamados daquela filial, sempre respeitando as regras de grupo acima.

---

## Exemplo testado

Cenário validado em um GLPI 11 real, com chamados abertos pela interface e pela API:

| Chamado | Aberto por | Categoria | Grupo requerente | Atribuído a |
|---|---|---|---|---|
| T1 | Caio (Comercial) | TI › Impressoras › Atolamento de papel | Comercial | TI |
| T2 | Duda (Financeiro) | RH › Benefícios › Vale-transporte | Financeiro | RH |
| T3 | Ana (RH) | TI › Hardware › Lentidão no computador | RH | TI |
| T4 | Caio (Comercial) | Financeiro › Reembolso de Despesas | Comercial | Financeiro |
| T5 | Tiago (TI) | Marketing › Criação de Peças › Arte para redes sociais | TI | Marketing |

O Caio também foi adicionado como **observador** do T2.

| Pessoa | Perfil + grupo | Vê |
|---|---|---|
| Administrador | Super-Admin | T1, T2, T3, T4, T5 |
| Caio | Self-Service + Comercial | T1, T4 (dele) e T2 (observador) |
| Duda | Self-Service + Financeiro | T2 |
| Gabi | Gestor de Equipe + Comercial | T1, T4 (abertos pela equipe Comercial) |
| Ana | Atendente de Área + RH | T2 (atribuído ao RH) e T3 (dela) |
| Rose | Gestor de Área + RH | T2 (atribuído ao RH) e T3 (aberto pela equipe RH) |
| Tiago | Técnico de TI + TI | T1, T3 (atribuídos à TI) e T5 (dele) |

---

## Cuidados

- **Perfis padrão do GLPI:** Admin, Supervisor, Technician, Hotliner, Observer e Read-Only continuam existindo e **veem todos os chamados**. Não os atribua a atendentes.
- **Integrações pela API:** ao abrir chamados pela API REST, informe o requerente (`_users_id_requester`). Sem ele, o GLPI só define o requerente depois de rodar as regras, e o grupo da equipe não é marcado. Pela interface, pelos Formulários e pelo coletor de e-mail isso acontece automaticamente.
- **Ajustes finos:** os perfis podem ser alterados em **Administração › Perfis**, e as regras em **Administração › Regras › Regras de negócio para chamados** (as criadas pelo instalador começam com "Grupo requerente:").
