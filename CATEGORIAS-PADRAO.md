# Categorias padrão de atendimento

Este é o catálogo de categorias que o [`install-glpi.sh`](servidor/install-glpi.sh) cria quando você responde **Sim** à pergunta:

```
Criar o catálogo padrão de categorias (TI, RH, Financeiro, Marketing)? [S/n]:
Áreas a criar, separadas por vírgula [TI,RH,Financeiro,Marketing]:
```

Você pode criar todas as áreas ou só algumas, por exemplo `TI` ou `TI,RH`.

## Como as categorias são organizadas

```
Área  ›  Grupo  ›  Categoria
 TI   › Impressoras › Atolamento de papel
```

- **Tipo:** cada categoria é marcada como **incidente** (algo parou de funcionar), **requisição** (um pedido ou solicitação) ou ambos. Ao abrir um chamado, o GLPI só mostra as categorias que combinam com o tipo escolhido.
- **Grupos e áreas** aparecem para incidente, para requisição ou para ambos, conforme as categorias de dentro deles. Por exemplo, **RH › Benefícios** só tem requisições, então não aparece num chamado de incidente.
- **Matriz e filiais:** todas as categorias ficam na matriz e valem para todas as filiais.
- **Autoatendimento:** todas ficam visíveis na interface simplificada.
- **Problemas e mudanças:** as categorias de **TI** também podem ser usadas em Problemas e Mudanças. As das outras áreas não.
- **Cascater:** com o plugin instalado, o usuário escolhe nível por nível (área, depois grupo, depois categoria), em vez de procurar numa lista única.

| Área | Grupos | Categorias finais |
|---|---|---|
| [TI](#ti) | 9 | 36 |
| [RH](#rh) | 7 | 13 |
| [Financeiro](#financeiro) | 6 | 9 |
| [Marketing](#marketing) | 5 | 9 |
| [Facilities](#facilities) | 3 | 6 |
| **Total** | | **73** (100 contando áreas e grupos) |

## TI

Suporte técnico: equipamentos, impressoras, rede, servidores, sistemas, e-mail, acessos, telefonia e segurança.

| Grupo | Categoria | Tipo |
|---|---|---|
| Hardware | Computador ou notebook não liga | Incidente |
| Hardware | Lentidão no computador | Incidente |
| Hardware | Periféricos (mouse, teclado, monitor) | Incidente e requisição |
| Hardware | Manutenção de notebook ou desktop | Incidente |
| Hardware | Mudança de posto ou equipamento | Requisição |
| Hardware | Solicitação de equipamento | Requisição |
| Impressoras | Impressora não imprime | Incidente |
| Impressoras | Atolamento de papel | Incidente |
| Impressoras | Troca de toner ou cartucho | Requisição |
| Impressoras | Instalação de impressora | Requisição |
| Rede e Internet | Sem acesso à internet | Incidente |
| Rede e Internet | Wi-Fi | Incidente e requisição |
| Rede e Internet | VPN | Incidente e requisição |
| Rede e Internet | Novo ponto de rede | Requisição |
| Servidores e Nuvem | Falha em servidor ou VM | Incidente |
| Servidores e Nuvem | Backup e restauração | Incidente e requisição |
| Servidores e Nuvem | Armazenamento e disco | Incidente e requisição |
| Sistemas e Softwares | Erro em sistema | Incidente |
| Sistemas e Softwares | ERP e Gestão | Incidente e requisição |
| Sistemas e Softwares | Relatórios e BI | Requisição |
| Sistemas e Softwares | Instalação de software | Requisição |
| Sistemas e Softwares | Atualização de software | Requisição |
| Sistemas e Softwares | Licenças | Requisição |
| E-mail e Colaboração | Problema no e-mail | Incidente |
| E-mail e Colaboração | Nova caixa ou lista de e-mail | Requisição |
| E-mail e Colaboração | Teams e reuniões online | Incidente e requisição |
| Acessos e Contas | Criação de usuário | Requisição |
| Acessos e Contas | Redefinição de senha | Requisição |
| Acessos e Contas | Conta bloqueada | Incidente |
| Acessos e Contas | Permissão em pastas ou sistemas | Requisição |
| Acessos e Contas | Desativação de usuário (desligamento) | Requisição |
| Telefonia | Ramal ou telefone com defeito | Incidente |
| Telefonia | Linha ou celular corporativo | Requisição |
| Segurança da Informação | Suspeita de vírus ou phishing | Incidente |
| Segurança da Informação | Incidente de segurança | Incidente |
| Segurança da Informação | Liberação de site ou firewall | Requisição |

## RH

Atendimento ao colaborador: folha, benefícios, ponto, férias, admissão e desligamento.

| Grupo | Categoria | Tipo |
|---|---|---|
| Folha de Pagamento | Dúvida no holerite | Requisição |
| Folha de Pagamento | Divergência no pagamento | Incidente |
| Benefícios | Vale-transporte | Requisição |
| Benefícios | Vale-refeição ou alimentação | Requisição |
| Benefícios | Plano de saúde ou odontológico | Requisição |
| Ponto e Jornada | Ajuste de ponto | Requisição |
| Ponto e Jornada | Banco de horas | Requisição |
| Férias e Afastamentos | Solicitação de férias | Requisição |
| Férias e Afastamentos | Atestados e afastamentos | Requisição |
| Admissão e Desligamento | Admissão de colaborador | Requisição |
| Admissão e Desligamento | Desligamento de colaborador | Requisição |
| Documentos e Declarações | *(a própria categoria)* | Requisição |
| Treinamento e Desenvolvimento | *(a própria categoria)* | Requisição |

## Financeiro

Pagamentos, recebimentos, notas fiscais, reembolsos e orçamento.

| Grupo | Categoria | Tipo |
|---|---|---|
| Contas a Pagar | Pagamento a fornecedor | Requisição |
| Contas a Pagar | Pagamento em atraso | Incidente |
| Contas a Receber | Emissão de boleto | Requisição |
| Contas a Receber | Baixa de pagamento | Requisição |
| Notas Fiscais | Emissão de nota fiscal | Requisição |
| Notas Fiscais | Erro em nota fiscal | Incidente |
| Reembolso de Despesas | *(a própria categoria)* | Requisição |
| Adiantamentos | *(a própria categoria)* | Requisição |
| Orçamento e Centro de Custo | *(a própria categoria)* | Requisição |

## Marketing

Criação de peças, site e redes sociais, eventos e comunicação interna.

| Grupo | Categoria | Tipo |
|---|---|---|
| Criação de Peças | Arte para redes sociais | Requisição |
| Criação de Peças | Material impresso | Requisição |
| Criação de Peças | Apresentação institucional | Requisição |
| Site e Redes Sociais | Atualização do site | Requisição |
| Site e Redes Sociais | Problema no site | Incidente |
| Site e Redes Sociais | Publicação em redes sociais | Requisição |
| Eventos e Patrocínios | *(a própria categoria)* | Requisição |
| Brindes e Materiais | *(a própria categoria)* | Requisição |
| Comunicação Interna | *(a própria categoria)* | Requisição |

## Facilities

Manutenção predial, climatização, infraestrutura física, mobiliário e segurança patrimonial.

| Grupo | Categoria | Tipo |
|---|---|---|
| Manutenção Predial | Ar-condicionado | Incidente e requisição |
| Manutenção Predial | Elétrica e iluminação | Incidente e requisição |
| Manutenção Predial | Hidráulica | Incidente |
| Mobiliário e Espaço | Reparo em mobiliário | Incidente |
| Mobiliário e Espaço | Mudança de layout | Requisição |
| Acesso e Chaves | Cópia de chave ou crachá | Requisição |

## Outros departamentos

Além das 5 áreas padrão, o instalador pergunta:

```
Outros departamentos que ATENDEM chamados, além dos padrão (ex.: Jurídico, Compras, Qualidade). Enter = nenhum:
```

Cada departamento informado vira uma área nova, com **3 categorias básicas**. Por exemplo, para `Jurídico`:

| Grupo | Categoria | Tipo |
|---|---|---|
| Dúvidas e orientações | *(a própria categoria)* | Requisição |
| Solicitações | *(a própria categoria)* | Requisição |
| Problemas e reclamações | *(a própria categoria)* | Incidente |

O departamento também ganha um **grupo de atendimento** com o mesmo nome, e as 3 categorias já ficam com esse grupo como responsável. Funciona igual às áreas padrão: os chamados caem sozinhos no grupo, e atendentes e gestores do departamento veem só os chamados dele (veja [PERFIS-E-PERMISSOES.md](PERFIS-E-PERMISSOES.md)).

Depois da instalação, crie as subcategorias específicas de cada departamento (por exemplo, *Jurídico › Contratos › Revisão de contrato*) em **Configurar › Listas suspensas › Categorias ITIL**. Lembre de preencher nelas o mesmo **grupo responsável**.

> Os departamentos que só **abrem** chamados (ex.: Comercial) não ganham categorias, só um grupo, porque eles não recebem chamados.

## Depois da instalação

As categorias são um ponto de partida. Para ajustar, acesse no GLPI **Configurar › Listas suspensas › Categorias ITIL**. Lá dá para:

- **renomear** ou **criar** categorias e subcategorias;
- **desativar** as que não fizerem sentido, desmarcando "Visível na interface simplificada", "Visível para incidentes" ou "Visível para requisições";
- definir o **grupo técnico** e o **técnico responsável** de cada área, para os chamados já caírem na fila certa;
- associar **modelos de chamado**, para pedir campos específicos por categoria.

> Para mudar o catálogo **antes** de instalar, por exemplo para usar em várias empresas, edite a função `category_catalog` no [`install-glpi.sh`](servidor/install-glpi.sh). Cada linha segue o formato `Área > Grupo > Categoria | Tipo`, onde o tipo é `I` (incidente), `R` (requisição) ou `A` (ambos).
