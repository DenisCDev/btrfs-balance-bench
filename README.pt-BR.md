# btrfs-balance-bench

[English](README.md) · **Português**

Mede o que o script `big-btrfs-balance` do BigLinux faz em inicializações seguidas e compara o script original com a mudança proposta em [biglinux/auto-rules-io#4](https://github.com/biglinux/auto-rules-io/pull/4).

O script original roda `btrfs balance start -dusage=50 -musage=50` depois de cada inicialização. Depois que o primeiro balance compacta os dados, o último chunk fica parcialmente cheio, volta a se encaixar no mesmo filtro na inicialização seguinte e é regravado. Assim, as inicializações seguintes gravam dados sem liberar espaço nenhum. O script corrigido só inicia um balance quando o espaço sem uso de um tipo chega a pelo menos um chunk, o mínimo necessário para liberar alguma coisa.

## Como funciona

Tudo roda num runner Ubuntu 24.04 do GitHub Actions, numa imagem btrfs em loopback montada com `compress-force=zstd,noatime` e `--direct-io=on`.

- `fill.py` monta a distribuição de arquivos: arquivos grandes e pequenos gravados intercalados, depois todos os pequenos e parte dos grandes apagados.
- `script.sh LABEL SCRIPT` roda o script real numa cópia nova da imagem por três inicializações seguidas. O script tem `/` e `/home` fixos no código, então só esses caminhos são apontados para o sistema de arquivos de teste. Cada inicialização registra o `btrfs filesystem df`, o tamanho dos chunks, o comando de balance iniciado e uma linha CSV: segundos, MiB gravados e MiB devolvidos ao espaço não alocado.
- `bench.sh LABEL "FILTROS" REP` roda um único `btrfs balance start` com os filtros informados e imprime a mesma linha CSV, para comparar filtros isoladamente.
- `contend.sh` mede um balance enquanto há outra leitura e gravação em andamento.

Scripts testados:

| arquivo | o que é |
|---|---|
| `big-btrfs-balance.orig` | o script do projeto original |
| `big-btrfs-balance.patched-v1` | primeira versão da correção, com limite fixo de 1 GiB para dados |
| `big-btrfs-balance.patched` | versão atual: lê o tamanho do chunk de metadados e limita os dois valores a 10% do tamanho do sistema de arquivos, como o kernel faz abaixo de 10 GiB |

Workflows: `bench.yml` (imagem de 12 GiB) e `small.yml` (imagem de 5 GiB, em que os chunks de dados têm 512 MiB). Os CSVs e logs brutos ficam como artefatos de cada execução.

## Resultados

Imagem de 12 GiB, três inicializações, três repetições cada:

| inicialização | original: gravado / devolvido ao espaço não alocado | corrigido: gravado / devolvido |
|---|---|---|
| 1 | 1437-1438 MiB / 4048 MiB | 1430 MiB / 4096 MiB |
| 2 | 494-495 MiB / 0 | 0 / 0 |
| 3 | 495 MiB / 0 | 0 / 0 |

Imagem de 5 GiB:

| inicialização | original: gravado / devolvido | corrigido: gravado / devolvido |
|---|---|---|
| 1 | 148 MiB / 472 MiB | 139 MiB / 520 MiB |
| 2 | 8 MiB / 0 (2 chunks realocados) | 0 / 0 |
| 3 | 9 MiB / 0 (2 chunks realocados) | 0 / 0 |

## Limites

O teste não rodou numa instalação do BigLinux, e os sistemas de arquivos de teste têm poucos chunks. O primeiro balance depois de muitas exclusões custa o mesmo com os dois scripts; só deixa de existir a regravação repetida nas inicializações seguintes.
