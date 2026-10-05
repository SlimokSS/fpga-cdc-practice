# FPGA CDC Practice

Этот репозиторий я сделал для практики Clock Domain Crossing (CDC) в SystemVerilog.

Основная цель была не просто написать работающий RTL, а разобраться, что реально происходит при передаче сигналов между независимыми тактовыми доменами: откуда берётся metastability, почему обычных двух триггеров хватает не всегда, зачем нужен Gray code, как работает REQ/ACK handshake и как всё это потом проверять в Quartus.

Сейчас в проекте есть две основные части:

- асинхронный FIFO;
- синхронизатор событий через REQ/ACK handshake.

Для симуляции использовал Icarus Verilog, для синтеза и анализа CDC — Intel Quartus Prime Lite 21.1.

## Структура проекта

```text
CDC/
├── constraints/
│   ├── async_fifo.sdc
│   └── pulse_sync.sdc
│
├── rtl/
│   ├── async_fifo.sv
│   └── pulse_sync.sv
│
├── tb/
│   ├── tb_async_fifo.sv
│   └── tb_pulse_sync.sv
│
└── README.md
```

# Асинхронный FIFO

Первой большой задачей был асинхронный FIFO, который передаёт данные между двумя независимыми clock domain.

Во время тестирования использовал:

```text
DEPTH = 16
WIDTH = 8
```

Для адресации памяти используются обычные binary pointers, а между clock domain передаются Gray pointers.

Указатели имеют дополнительный бит:

```text
ADDR_W = $clog2(DEPTH)

wr_bin  [ADDR_W:0]
rd_bin  [ADDR_W:0]
wr_gray [ADDR_W:0]
rd_gray [ADDR_W:0]
```

Дополнительный бит нужен для определения wrap-around и состояния `full`.

## Binary и Gray pointers

Следующий binary pointer вычисляется только при реальной транзакции:

```systemverilog
wr_bin_next = wr_bin + wr_fire;
rd_bin_next = rd_bin + rd_fire;
```

После этого binary значение переводится в Gray code:

```systemverilog
wr_gray_next = wr_bin_next ^ (wr_bin_next >> 1);
rd_gray_next = rd_bin_next ^ (rd_bin_next >> 1);
```

Gray code используется потому, что между соседними значениями меняется только один бит. Это сильно удобнее для CDC, чем передавать обычный binary counter, где одновременно могут переключаться несколько бит.

## Синхронизация указателей

Write pointer передаётся в read domain через двухтриггерный synchronizer:

```text
wr_gray
   ↓
wr_gray_sync1
   ↓
wr_gray_sync2
```

Read pointer аналогично передаётся в write domain:

```text
rd_gray
   ↓
rd_gray_sync1
   ↓
rd_gray_sync2
```

В каждом домене используется только уже синхронизированное значение указателя из другого домена.

## Empty

FIFO считается пустым, когда следующий read pointer совпадает с синхронизированным write pointer:

```systemverilog
empty_next = (rd_gray_next == wr_gray_sync2);
```

## Full

Для определения `full` используется сравнение следующего write Gray pointer с синхронизированным read Gray pointer с инверсией двух старших битов:

```systemverilog
full_next =
    (wr_gray_next ==
        {~rd_gray_sync2[ADDR_W:ADDR_W-1],
          rd_gray_sync2[ADDR_W-2:0]});
```

## Ready/valid

На write стороне:

```text
wr_fire = s_valid && s_ready
```

На read стороне:

```text
rd_fire = m_valid && m_ready
```

То есть указатели и память изменяются только когда транзакция реально произошла.

## Память

Память FIFO описана как массив:

```systemverilog
logic [WIDTH-1:0] mem [0:DEPTH-1];
```

Quartus для FIFO 16x8 смог вывести её в embedded dual-port RAM.

Получилось:

```text
16 x 8 = 128 бит
```

Саму память я не сбрасываю reset'ом. Состояние FIFO определяется указателями и флагами `full/empty`, поэтому очищать все ячейки памяти нет необходимости.

## Reset CDC

Внешний `rst_n` асинхронно устанавливает reset, но выход из reset происходит синхронно отдельно в каждом clock domain.

Для write domain:

```text
rst_n
  ↓
rst_n_wr1
  ↓
rst_n_wr
```

Для read domain:

```text
rst_n
  ↓
rst_n_rd1
  ↓
rst_n_rd
```

Так логика не выходит из reset напрямую по асинхронному фронту.

# Проверка async FIFO

В testbench проверяются:

- reset;
- обычная запись;
- обычное чтение;
- заполнение FIFO;
- состояние `full`;
- опустошение FIFO;
- состояние `empty`;
- попытка записи при `full`;
- попытка чтения при `empty`;
- одновременная запись и чтение;
- wrap-around указателей;
- несколько полных циклов работы FIFO.

Запуск симуляции:

```powershell
iverilog -g2012 -Wall -s tb_async_fifo -o simv rtl/async_fifo.sv tb/tb_async_fifo.sv
vvp .\simv
```

# Async FIFO в Quartus

После функциональной симуляции я отдельно проверял CDC уже в Quartus.

Первые триггеры synchronizer chains были помечены через:

```text
Synchronizer Identification = Forced If Asynchronous
```

Для FIFO Quartus нашёл 12 synchronizer chains:

```text
5 бит rd_gray
5 бит wr_gray
1 reset synchronizer write domain
1 reset synchronizer read domain
```

Для всех цепочек Quartus показал:

```text
Typical MTBF > 1 Billion years
```

## SDC для Gray bus

Кроме обычных synchronizer FF, Gray bus нужно ещё правильно ограничить физически.

Для этого в `async_fifo.sdc` используются:

```text
set_max_delay
set_min_delay
set_max_skew
```

Первые ступени synchronizer'ов выбираются именно по data pins:

```tcl
set wr_gray_sync1_data \
    [get_pins -hierarchical {*wr_gray_sync1*|d *wr_gray_sync1*|asdata}]

set rd_gray_sync1_data \
    [get_pins -hierarchical {*rd_gray_sync1*|d *rd_gray_sync1*|asdata}]
```

`set_max_delay` ограничивает максимальную задержку каждого Gray bit.

`set_min_delay` задаёт нижнюю границу задержки.

`set_max_skew` ограничивает разброс задержек между битами Gray bus.

В итоговом TimeQuest report нарушений не было.

Для Gray bus получилось примерно:

```text
write max delay worst slack: +17.656 ns
read max delay worst slack:  +22.606 ns

write min delay worst slack: +0.861 ns
read min delay worst slack:  +0.864 ns

actual max skew:    1.453 ns
required max skew: 18.000 ns
worst skew slack: +16.547 ns
```

Из этого задания я отдельно понял важную вещь: зелёный SDC report ещё не означает, что всё сделано правильно.

Нужно обязательно смотреть реальные:

```text
From
To
Launch Clock
Latch Clock
```

и проверять, что constraint попал именно на те physical paths, которые я хотел ограничить.

# Pulse/Event CDC

Следующая часть проекта — передача одиночных событий между разными clock domain.

Первое, что стало понятно: обычный 2-FF synchronizer подходит для передачи стабильного level, но не гарантирует передачу короткого pulse.

Если pulse появился и исчез между двумя фронтами destination clock, принимающий домен вообще может его не увидеть.

## Toggle synchronizer

Сначала я сделал классический toggle synchronizer.

Каждое source событие меняет состояние одного бита:

```text
0 -> 1
1 -> 0
```

Этот бит проходит через 2-FF synchronizer в destination domain.

Дальше текущее значение сравнивается с предыдущим:

```text
toggle_sync2 XOR toggle_sync2_d
```

Если состояние изменилось, в destination domain появляется pulse длиной один такт.

Это решает проблему короткого source pulse, но появляется другая проблема.

Если два события произошли слишком быстро:

```text
0 -> 1 -> 0
```

и destination не успел увидеть промежуточное состояние `1`, то для него сигнал вообще не изменился.

То есть простой toggle synchronizer не умеет гарантированно передавать несколько событий, которые идут слишком близко друг к другу.

# REQ/ACK handshake

Чтобы это исправить, я переделал передачу события в handshake с REQ и ACK.

В source domain есть:

```text
req_toggle
```

REQ проходит в destination:

```text
req_toggle
    ↓
req_toggle_sync1
    ↓
req_toggle_sync2
```

В destination domain есть:

```text
ack_toggle
```

ACK возвращается обратно:

```text
ack_toggle
    ↓
ack_toggle_sync1
    ↓
ack_toggle_sync2
```

Source может принять новое событие только когда:

```systemverilog
src_ready = (req_toggle == ack_toggle_sync2);
```

Событие принимается при:

```systemverilog
event_src && src_ready
```

После этого `req_toggle` меняет состояние.

Destination обнаруживает новый request через:

```systemverilog
req_toggle_sync2 != ack_toggle
```

В этот момент появляется:

```text
event_dst = 1
```

на один такт `clk_dst`.

После обработки destination подтверждает событие:

```systemverilog
ack_toggle <= req_toggle_sync2;
```

После этого ACK проходит обратно через 2-FF synchronizer и `src_ready` снова становится единицей.

Получается такой цикл:

```text
src_ready = 1
      ↓
source event
      ↓
REQ меняется
      ↓
src_ready = 0
      ↓
REQ проходит CDC
      ↓
event_dst
      ↓
ACK меняется
      ↓
ACK проходит CDC обратно
      ↓
src_ready = 1
```

Главное отличие от обычного toggle synchronizer — source теперь получает backpressure.

Если предыдущий request ещё не обработан, новый request не принимается.

При этом producer должен соблюдать handshake: если у него уже есть новое событие, а `src_ready = 0`, он должен дождаться готовности.

# Проверка pulse_sync

Для testbench использовал:

```text
clk_src:
T = 14 ns
f ≈ 71.43 MHz

clk_dst:
T = 50 ns
f = 20 MHz
```

Проверяются:

- reset;
- состояние `src_ready` после reset;
- обычная передача события;
- несколько последовательных событий;
- переключение REQ в обе стороны;
- backpressure;
- возврат ACK;
- работа после повторного reset.

Также проверяется ситуация, когда source хочет отправить несколько событий подряд.

Второе событие ждёт возвращения `src_ready`, поэтому принятое событие уже не может потеряться внутри CDC.

Запуск:

```powershell
iverilog -g2012 -Wall -s tb_pulse_sync -o simv rtl/pulse_sync.sv tb/tb_pulse_sync.sv
vvp .\simv
```

Успешная симуляция заканчивается сообщением:

```text
tb_pulse_sync is finished
```

# Pulse sync в Quartus

REQ и ACK synchronizer chains также были помечены через:

```text
Synchronizer Identification = Forced If Asynchronous
```

Quartus нашёл четыре synchronizer chains:

```text
req_toggle -> req_toggle_sync1 -> req_toggle_sync2

ack_toggle -> ack_toggle_sync1 -> ack_toggle_sync2

rst_n -> rst_n_src1 -> rst_n_src

rst_n -> rst_n_dst1 -> rst_n_dst
```

Для всех четырёх:

```text
Typical MTBF > 1 Billion years
```

## REQ

REQ идёт из быстрого clock domain в медленный:

```text
Source Clock:
clk_src ≈ 71.43 MHz

Synchronization Clock:
clk_dst = 20 MHz

Synchronization Registers:
2

Available Settling Time:
97.864 ns

Data Toggle Rate:
8.929 million transitions/s
```

## ACK

ACK идёт обратно из медленного clock domain в быстрый:

```text
Source Clock:
clk_dst = 20 MHz

Synchronization Clock:
clk_src ≈ 71.43 MHz

Synchronization Registers:
2

Available Settling Time:
25.129 ns

Data Toggle Rate:
2.5 million transitions/s
```

У ACK settling time заметно меньше, потому что принимающий clock быстрее.

При этом даже для ACK Quartus показывает MTBF больше одного миллиарда лет.

# Что я вынес из этого проекта

После этой практики CDC для меня перестал быть просто правилом "поставь два триггера".

Основные вещи, которые я разобрал:

- metastability нельзя полностью убрать, можно только сильно уменьшить вероятность её распространения;
- 2-FF synchronizer подходит для single-bit level;
- короткий pulse через обычный 2-FF synchronizer может полностью потеряться;
- toggle synchronizer позволяет передать короткое событие;
- два быстрых события могут схлопнуться в обычном toggle synchronizer;
- REQ/ACK handshake гарантирует доставку принятого события;
- backpressure является частью интерфейса;
- multi-bit данные нельзя просто независимо синхронизировать по битам;
- для потока multi-bit данных удобно использовать asynchronous FIFO;
- Gray code хорошо подходит для передачи FIFO pointers;
- reset тоже является CDC-проблемой;
- asynchronous assert + synchronous deassert позволяет безопаснее работать с reset;
- MTBF сильно зависит от available settling time;
- constraints нужно проверять не только по наличию violations, но и по тому, какие реальные пути они ограничивают;
- SDC, который успешно выполняется, всё равно может проверять вообще не те пути.