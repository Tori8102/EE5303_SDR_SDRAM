*Ho Chi Minh City University of Technology - Vietnam National University, Ho Chi Minh City*

*Học kì 221 - Năm học 2022-2023*
# Logic Design Project
<ul>
<li>Hội đồng : Đồ án thiết kế luận lí 6</li>
<li>Giảng viên hướng dẫn : ThS. Đoàn Minh Vững </li>
<li>Thư kí hội đồng: Huỳnh Hoàng Kha</li>
</ul>

## Sinh viên thực hiện:
| Name | ID |
| :---- | :----: |
| Nguyễn Ngọc Trí | 2012286 |

## File github:
Folder STM32: Chứa code để nạp vào vi mạch tích hợp vi điều khiển STM32F103RB. <br>
Cấu trúc các file source code:
| File | Chức năng |
| :---- | :---- | 
| button.h và button.c | Cấu trúc thực hiện chức năng nút nhấn |
| software_timer.h và software_timer.c | Cấu trúc thực hiện chức năng quản lí thời gian các task timer |
| lcd1602.h và lcd1602.c | Cấu trúc lập trình Led LCD 1602 |
| rtc.h và rtc.c | Cấu trúc lập trình xử lí dữ liệu thời gian thực |
| global.h và global.c | Chứa danh sách các cấu trúc, các biến, các trạng thái |
| fsm_clock.h và fsm_clock.c | Lập trình máy trạng thái thực hiện các tính năng của đồng hồ |
| main.h và main.c | File chạy chương trình chính |

## Cấu hình STM32F103RB:
*RCC*: HSE và LSE ở chế độ Crystal / Ceramic Resonator. Sử dụng thạch anh ngoại HSE 62.5 kHZ. <br>
*Tần số*: 64 MHz. <br>
*Time tick cycle*: 10ms. <br>
*SYS*: Serial Wire. <br>
*RTC*: Activate Clock Source và Activate Calendar. <br>
*TIM2*: Prescaler - 63999, Counter Period - 9. <br>
*TIM3*: Prescaler - 639, Counter Period - 99. <br>

*Sơ đồ các chân*:
| Chân | Loại chân | Tên chân | Chức năng |
| :---- | :----: | :----: | :---- |
| PA6 | TIM3_CH1 | | Config signal buzzer |
| PC5 | Output | | D4-LCD |
| PC6 | Output | | D5-LCD |
| PC8 | Output | | D6-LCD |
| PC9 | Output | | D7-LCD |
| PB8 | Output | | EN-LCD |
| PB9 | Output | | RS-LCD |
| PC7 | Input - Pullup | MODE | Mode |
| PA9 | Input - Pullup | START_UP | Start (Mode 2) or Up (Mode 3) |
| PA8 | Input - Pullup | STOP_DOWN | Stop (Mode 2) or Down (Mode 3) |
| PB10 | Input - Pullup | SAVE_SET | Save (Mode 2) or Set (Mode 3) |
| PB4 | Input - Pullup | CLEAR | Clear buzzer, clear value |
| PB5 | Input - Pullup | MEMCALL | Memcall (Mode 2) |

