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
| [TI](#ti) | 8 | 28 |
| [RH](#rh) | 7 | 13 |
| [Financeiro](#financeiro) | 6 | 9 |
| [Marketing](#marketing) | 5 | 9 |
| **Total** | | **59** (81 contando áreas e grupos) |

## TI

Suporte técnico: equipamentos, impressoras, rede, sistemas, e-mail, acessos, telefonia e segurança.

| Grupo | Categoria | Tipo |
|---|---|---|
| Hardware | Computador ou notebook não liga | Incidente |
| Hardware | Lentidão no computador | Incidente |
| Hardware | Periféricos (mouse, teclado, monitor) | Incidente e requisição |
| Hardware | Solicitação de equipamento | Requisição |
| Impressoras | Impressora não imprime | Incidente |
| Impressoras | Atolamento de papel | Incidente |
| Impressoras | Troca de toner ou cartucho | Requisição |
| Impressoras | Instalação de impressora | Requisição |
| Rede e Internet | Sem acesso à internet | Incidente |
| Rede e Internet | Wi-Fi | Incidente e requisição |
| Rede e Internet | VPN | Incidente e requisição |
| Rede e Internet | Novo ponto de rede | Requisição |
| Sistemas e Softwares | Erro em sistema | Incidente |
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

## Depois da instalação

As categorias são um ponto de partida. Para ajustar, acesse no GLPI **Configurar › Listas suspensas › Categorias ITIL**. Lá dá para:

- **renomear** ou **criar** categorias e subcategorias;
- **desativar** as que não fizerem sentido, desmarcando "Visível na interface simplificada", "Visível para incidentes" ou "Visível para requisições";
- definir o **grupo técnico** e o **técnico responsável** de cada área, para os chamados já caírem na fila certa;
- associar **modelos de chamado**, para pedir campos específicos por categoria.

> Para mudar o catálogo **antes** de instalar, por exemplo para usar em várias empresas, edite a função `category_catalog` no [`install-glpi.sh`](servidor/install-glpi.sh). Cada linha segue o formato `Área > Grupo > Categoria | Tipo`, onde o tipo é `I` (incidente), `R` (requisição) ou `A` (ambos).
