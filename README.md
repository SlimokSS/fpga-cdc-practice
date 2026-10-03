# CDC Practice — Asynchronous FIFO

Учебный проект по Clock Domain Crossing (CDC) на SystemVerilog.

Цель проекта — разобраться не только в RTL-реализации asynchronous FIFO, но и в том, что происходит после синтеза: metastability, synchronizer chains, Gray-code pointers, dual-clock RAM, reset CDC, MTBF analysis и физические timing constraints в Intel Quartus TimeQuest.

Проект реализован для FPGA:

- Intel Cyclone IV E
- EP4CE6F17C8N
- Quartus Prime Lite 21.1

## Структура проекта

```text
CDC/
├── README.md
├── constraints/
│   └── async_fifo.sdc
├── rtl/
│   └── async_fifo.sv
└── tb/
    └── tb_async_fifo.sv
```

## Основные параметры

В текущей конфигурации FIFO используется:

```text
DATA WIDTH = 8 bit
DEPTH      = 16
clk_wr     = 50 MHz / 20 ns
clk_rd     = 40 MHz / 25 ns
```

Write и read части работают в независимых clock domains.

Интерфейс построен в стиле ready/valid.

Write side:

```text
s_data
s_valid
s_ready
```

Read side:

```text
m_data
m_valid
m_ready
```

Передача происходит только при handshake:

```text
wr_fire = s_valid && s_ready
rd_fire = m_valid && m_ready
```

---

# Архитектура asynchronous FIFO

В synchronous FIFO можно было бы использовать общий `count`.

В asynchronous FIFO это невозможно сделать напрямую, потому что запись и чтение происходят от разных clocks.

Поэтому FIFO использует два независимых pointer:

```text
wr_bin
rd_bin
```

Binary pointers используются для:

- адресации RAM;
- локального инкремента;
- вычисления следующего pointer.

Для передачи состояния pointer между clock domains binary pointer преобразуется в Gray code:

```systemverilog
gray = binary ^ (binary >> 1);
```

Используются:

```text
wr_gray
rd_gray
```

Главное свойство Gray code:

> между двумя соседними значениями изменяется только один бит.

Это делает Gray code удобным для передачи счетчиков между асинхронными clock domains.

---

# Pointer width

При:

```text
DEPTH = 16
```

адресная ширина равна:

```systemverilog
ADDR_W = $clog2(DEPTH);
```

То есть:

```text
ADDR_W = 4
```

Но сами pointers имеют ширину:

```text
ADDR_W + 1 = 5 bit
```

Дополнительный старший бит используется для определения wrap-around.

RAM адресуется только младшими битами:

```systemverilog
wr_bin[ADDR_W-1:0]
rd_bin[ADDR_W-1:0]
```

Для `DEPTH = 16` это:

```text
wr_bin[3:0]
rd_bin[3:0]
```

Пятый бит в адрес RAM не идет.

---

# Gray-code pointer crossing

Write pointer передается из `clk_wr` domain в `clk_rd` domain:

```text
wr_gray
   |
   v
wr_gray_sync1
   |
   v
wr_gray_sync2
```

Read pointer передается в обратном направлении:

```text
rd_gray
   |
   v
rd_gray_sync1
   |
   v
rd_gray_sync2
```

Для каждого Gray bit используется двухступенчатый synchronizer.

Первый FF может попасть в metastability.

Второй FF дает первому дополнительное время для выхода из metastable state перед использованием значения остальной логикой.

---

# Empty detection

Флаг `empty` формируется только внутри read domain.

Используется следующий read pointer:

```systemverilog
rd_bin_next = rd_bin + rd_fire;
rd_gray_next = rd_bin_next ^ (rd_bin_next >> 1);
```

FIFO считается пустым, если следующий read pointer совпадает с синхронизированным write pointer:

```systemverilog
empty_next = (rd_gray_next == wr_gray_sync2);
```

Таким образом read-side логика никогда напрямую не использует asynchronous `wr_gray`.

---

# Full detection

Флаг `full` формируется только внутри write domain.

Следующий write pointer:

```systemverilog
wr_bin_next = wr_bin + wr_fire;
wr_gray_next = wr_bin_next ^ (wr_bin_next >> 1);
```

Для определения состояния `full` следующий write Gray pointer сравнивается с синхронизированным read Gray pointer, у которого инвертированы два старших бита:

```systemverilog
full_next =
    (wr_gray_next ==
        {~rd_gray_sync2[ADDR_W:ADDR_W-1],
          rd_gray_sync2[ADDR_W-2:0]});
```

Это позволяет определить ситуацию, когда write pointer находится на один полный оборот впереди read pointer.

---

# FIFO memory

Память описана как:

```systemverilog
logic [WIDTH-1:0] mem [0:DEPTH-1];
```

Запись выполняется только в `clk_wr` domain:

```systemverilog
always_ff @(posedge clk_wr)
    if (wr_fire)
        mem[wr_bin[ADDR_W-1:0]] <= s_data;
```

Read address определяется текущим `rd_bin`.

Quartus распознал память как dual-port RAM.

Для:

```text
WIDTH = 8
DEPTH = 16
```

размер памяти составляет:

```text
16 × 8 = 128 bit
```

RAM специально не сбрасывается reset-сигналом.

После reset pointers возвращаются в начальное состояние, FIFO становится `empty`, поэтому старые данные внутри RAM считаются невалидными и не используются.

---

# Reset CDC

Внешний:

```text
rst_n
```

является asynchronous относительно обоих clocks.

Для каждого clock domain реализован отдельный reset synchronizer.

Write domain:

```text
rst_n
  |
  v
rst_n_wr1
  |
  v
rst_n_wr
```

Read domain:

```text
rst_n
  |
  v
rst_n_rd1
  |
  v
rst_n_rd
```

Используется принцип:

```text
asynchronous assertion
synchronous deassertion
```

То есть reset включается сразу, независимо от clocks.

Выход из reset происходит синхронно отдельно относительно `clk_wr` и `clk_rd`.

Это уменьшает риск проблем при release reset около активного clock edge.

Во время local reset интерфейс FIFO блокируется:

```systemverilog
s_ready = !full && rst_n_wr;
m_valid = !empty && rst_n_rd;
```

Поэтому во время reset не происходит случайных read/write transactions.

---

# Quartus Synchronizer Identification

Quartus автоматически распознал synchronizer chains, но изначально не рассчитывал для них MTBF.

Через Assignment Editor первые stages synchronizers были отмечены как:

```text
Synchronizer Identification
Forced If Asynchronous
```

Были отмечены:

```text
wr_gray_sync1[4:0]
rd_gray_sync1[4:0]

rst_n_wr1
rst_n_rd1
```

Всего Quartus обнаружил:

```text
12 synchronizer chains
```

Из них:

```text
5 — wr_gray crossing
5 — rd_gray crossing
1 — write reset synchronizer
1 — read reset synchronizer
```

После правильного Synchronizer Identification Quartus начал включать эти chains в metastability analysis.

Для всех цепочек был получен результат:

```text
Typical MTBF > 1 Billion years
```

MTBF здесь является статистической оценкой вероятности распространения metastability и не означает буквальный срок службы FPGA.

---

# Gray bus physical timing constraints

Gray code и 2FF synchronizer решают только часть CDC-проблемы.

После Place & Route разные Gray bits могут иметь разные routing delays.

Например, один Gray transition может идти настолько долго, что следующий transition по другому bit физически придет в destination domain раньше предыдущего.

Поэтому Gray bus дополнительно ограничивается через SDC.

---

## Выбор data pins synchronizer

Если использовать весь register:

```tcl
[get_registers {*wr_gray_sync1*}]
```

Quartus может включить в анализ не только data input, но и:

```text
clock
clear/reset
other control pins
```

На практике это привело к тому, что `Report Max Skew` начал анализировать:

```text
rst_n -> clrn
```

вместо Gray data paths.

Поэтому после анализа post-fit netlist используются конкретные data pins:

```tcl
set wr_gray_sync1_data \
    [get_pins -hierarchical {*wr_gray_sync1*|d *wr_gray_sync1*|asdata}]

set rd_gray_sync1_data \
    [get_pins -hierarchical {*rd_gray_sync1*|d *rd_gray_sync1*|asdata}]
```

Quartus использовал как обычные `d` pins, так и `asdata`, поэтому в collection включены оба варианта.

Для каждого synchronizer было найдено ровно 5 data pins.

---

# Maximum delay

Каждый отдельный Gray bit ограничивается одним source clock period.

Для write pointer source clock:

```text
clk_wr = 20 ns
```

Используется:

```tcl
set_max_delay \
    -from [get_clocks {clk_wr}] \
    -to $wr_gray_sync1_data \
    20.000
```

Для read pointer:

```text
clk_rd = 25 ns
```

Используется:

```tcl
set_max_delay \
    -from [get_clocks {clk_rd}] \
    -to $rd_gray_sync1_data \
    25.000
```

TimeQuest показал 5 paths для каждого направления.

Для `wr_gray`:

```text
Worst setup slack = 17.656 ns
```

При requirement:

```text
20.000 ns
```

получаем worst physical delay примерно:

```text
20.000 - 17.656 = 2.344 ns
```

Для `rd_gray`:

```text
Worst setup slack = 22.606 ns
```

При requirement:

```text
25.000 ns
```

worst delay составляет примерно:

```text
25.000 - 22.606 = 2.394 ns
```

---

# Minimum delay

Обычный `set_false_path` использовать для этих Gray paths оказалось неудобно.

После `set_false_path` Quartus переставал учитывать эти paths в `Report Max Skew`.

Поэтому используется explicit minimum delay:

```tcl
set_min_delay \
    -from [get_clocks {clk_wr}] \
    -to $wr_gray_sync1_data \
    0.000
```

и:

```tcl
set_min_delay \
    -from [get_clocks {clk_rd}] \
    -to $rd_gray_sync1_data \
    0.000
```

В результате пути остаются внутри timing graph и могут одновременно участвовать в:

```text
set_max_delay
set_min_delay
set_max_skew
```

---

# Maximum skew

Кроме абсолютной задержки каждого bit контролируется разброс задержек между Gray bits.

Для write-side используется:

```tcl
set_max_skew \
    -to $wr_gray_sync1_data \
    -get_skew_value_from_clock_period src_clock_period \
    -skew_value_multiplier 0.900
```

Source period:

```text
20 ns
```

Поэтому maximum allowed skew:

```text
0.9 × 20 ns = 18 ns
```

Для read-side:

```tcl
set_max_skew \
    -to $rd_gray_sync1_data \
    -get_skew_value_from_clock_period src_clock_period \
    -skew_value_multiplier 0.900
```

Source period:

```text
25 ns
```

Maximum skew:

```text
0.9 × 25 ns = 22.5 ns
```

---

# Report Max Skew result

Quartus обнаружил:

```text
20 paths
0 violations
```

Для worst-case write-side pair:

```text
From Node      wr_gray[0]
To Node        wr_gray_sync1[0]
Launch Clock   clk_wr
Latch Clock    clk_rd
```

и второй путь:

```text
From Node      wr_gray[2]
To Node        wr_gray_sync1[2]
Launch Clock   clk_wr
Latch Clock    clk_rd
```

Результат:

```text
Required Skew = 18.000 ns
Actual Skew   = 1.453 ns
Slack         = 16.547 ns
```

Это подтверждает, что constraint применяется именно к Gray CDC data paths.

---

# SDC

Файл:

```text
constraints/async_fifo.sdc
```

содержит:

```tcl
create_clock -name clk_wr -period 20.000 [get_ports {clk_wr}]
create_clock -name clk_rd -period 25.000 [get_ports {clk_rd}]

derive_clock_uncertainty

set wr_gray_sync1_data \
    [get_pins -hierarchical {*wr_gray_sync1*|d *wr_gray_sync1*|asdata}]

set rd_gray_sync1_data \
    [get_pins -hierarchical {*rd_gray_sync1*|d *rd_gray_sync1*|asdata}]

set_max_skew \
    -to $wr_gray_sync1_data \
    -get_skew_value_from_clock_period src_clock_period \
    -skew_value_multiplier 0.900

set_max_skew \
    -to $rd_gray_sync1_data \
    -get_skew_value_from_clock_period src_clock_period \
    -skew_value_multiplier 0.900

set_max_delay \
    -from [get_clocks {clk_wr}] \
    -to $wr_gray_sync1_data \
    20.000

set_max_delay \
    -from [get_clocks {clk_rd}] \
    -to $rd_gray_sync1_data \
    25.000

set_min_delay \
    -from [get_clocks {clk_wr}] \
    -to $wr_gray_sync1_data \
    0.000

set_min_delay \
    -from [get_clocks {clk_rd}] \
    -to $rd_gray_sync1_data \
    0.000
```

---

# Testbench

Для FIFO написан self-checking testbench:

```text
tb/tb_async_fifo.sv
```

Testbench использует независимые clocks.

В симуляции проверяются:

- reset;
- одиночная запись;
- одиночное чтение;
- сохранение порядка данных;
- заполнение FIFO;
- состояние `full`;
- невозможность записи при `full`;
- опустошение FIFO;
- состояние `empty`;
- невозможность чтения при `empty`;
- одновременная запись и чтение;
- работа при разных write/read frequencies;
- многократный pointer wrap-around.

В concurrent test writer и reader работают одновременно.

Передается последовательность из 64 значений, поэтому pointers несколько раз проходят полный круг FIFO.

---

# Simulation

Для симуляции использовался Icarus Verilog.

Запуск из корня проекта:

```bash
iverilog -g2012 -Wall -s tb_async_fifo -o simv rtl/async_fifo.sv tb/tb_async_fifo.sv
vvp simv
```

При корректной работе testbench завершается без ошибок.

---

# Что было изучено

В рамках проекта были практически разобраны:

- Clock Domain Crossing;
- metastability;
- двухступенчатые synchronizers;
- Gray code;
- asynchronous FIFO;
- binary и Gray pointers;
- extra wrap bit;
- full/empty detection;
- dual-clock RAM;
- ready/valid handshake;
- asynchronous reset assertion;
- synchronous reset deassertion;
- Quartus Synchronizer Identification;
- MTBF analysis;
- Quartus TimeQuest;
- `set_max_delay`;
- `set_min_delay`;
- `set_max_skew`;
- post-fit pins;
- влияние physical routing на CDC;
- проверка SDC через реальные timing reports.

---

# Основной вывод

Корректный CDC — это не только правильный SystemVerilog RTL.

Нужно учитывать сразу несколько уровней:

```text
RTL architecture
        +
Gray encoding
        +
synchronizers
        +
metastability
        +
reset strategy
        +
physical routing
        +
timing constraints
        +
post-fit analysis
        +
verification
```

Особенно важный практический вывод:

> SDC constraint нельзя считать правильным только потому, что Quartus его принял и отчет зеленый.

Нужно обязательно проверять:

```text
From Node
To Node
Launch Clock
Latch Clock
Actual Delay / Skew
Required Delay / Skew
Slack
```

В ходе проекта несколько syntactically valid constraints сначала анализировали не те paths. Только после просмотра post-fit timing reports удалось убедиться, что TimeQuest действительно проверяет нужные Gray CDC connections.

Этот проект является практической основой для дальнейшего изучения CDC-схем: pulse synchronization, toggle synchronization, handshake CDC и других способов передачи информации между независимыми clock domains.