/* Private includes -----------------------------------------------------------*/
//includes
#include "string.h"
#include "stdio.h"

#include "main.h"
#include "stm32f4xx_it.h"
#include "rtc.h"

#include "user_TasksInit.h"
#include "user_MessageSendTask.h"

#include "ui.h"
#include "ui_EnvPage.h"
#include "ui_HRPage.h"
#include "ui_SPO2Page.h"
#include "ui_HomePage.h"
#include "ui_DateTimeSetPage.h"

#include "HWDataAccess.h"
#include "version.h"

/* Private typedef -----------------------------------------------------------*/

/* Private define ------------------------------------------------------------*/
#define OV_COMMAND_BUFFER_SIZE 25U
#define STOPWATCH_BOOT_COUNTER_REGISTER RTC_BKP_DR1

/* Private variables ---------------------------------------------------------*/
struct
{
	RTC_DateTypeDef nowdate;
	RTC_TimeTypeDef nowtime;
	int8_t humi;
	int8_t temp;
	uint8_t HR;
	uint8_t SPO2;
	uint16_t stepNum;
}BLEMessage;

typedef struct
{
	uint32_t session_id;
	RTC_DateTypeDef end_date;
	RTC_TimeTypeDef end_time;
	uint32_t duration_ms;
} StopwatchLogRecord_t;

typedef enum
{
	CLOCK_SET_OK = 0,
	CLOCK_SET_BAD_LENGTH,
	CLOCK_SET_BAD_TIME,
	CLOCK_SET_RTC_ERROR
} ClockSetResult_t;

static volatile StopwatchState_t Stopwatch_State = STOPWATCH_STATE_IDLE;
static volatile uint32_t Stopwatch_Elapsed = 0U;
static volatile uint32_t Stopwatch_ActiveSession = 0U;
static uint32_t Stopwatch_BootId = 0U;
static uint32_t Stopwatch_NextSession = 1U;
static uint8_t Stopwatch_Initialized = 0U;
static StopwatchLogRecord_t Stopwatch_Log[STOPWATCH_LOG_CAPACITY];
static uint8_t Stopwatch_LogCount = 0U;
static uint8_t Stopwatch_LogWriteIndex = 0U;

/* Private function prototypes -----------------------------------------------*/

static uint32_t RotateLeft32(uint32_t value, uint8_t shift)
{
	return (value << shift) | (value >> (32U - shift));
}

static uint8_t CommandLength(const uint8_t *str)
{
	uint8_t length = 0U;
	while(length < OV_COMMAND_BUFFER_SIZE && str[length] != '\0')
	{
		length++;
	}
	return length;
}

static uint8_t CommandEquals(const uint8_t *str, uint8_t length, const char *expected)
{
	size_t expected_length = strlen(expected);
	return (uint8_t)(length == expected_length && memcmp(str, expected, expected_length) == 0);
}

static uint8_t CommandStartsWith(const uint8_t *str, uint8_t length, const char *prefix)
{
	size_t prefix_length = strlen(prefix);
	return (uint8_t)(length >= prefix_length && memcmp(str, prefix, prefix_length) == 0);
}

static uint8_t IsLeapYear(uint16_t year)
{
	return (uint8_t)(((year % 4U) == 0U && (year % 100U) != 0U) || (year % 400U) == 0U);
}

static uint8_t DaysInMonth(uint16_t year, uint8_t month)
{
	static const uint8_t days[] = {31U, 28U, 31U, 30U, 31U, 30U, 31U, 31U, 30U, 31U, 30U, 31U};
	if(month == 2U && IsLeapYear(year))
	{
		return 29U;
	}
	return days[month - 1U];
}

static uint8_t ParseTwoDigits(const uint8_t *str, uint8_t index)
{
	return (uint8_t)((str[index] - '0') * 10U + (str[index + 1U] - '0'));
}

static uint8_t AllDigits(const uint8_t *str, uint8_t begin, uint8_t end)
{
	uint8_t index;
	for(index = begin; index < end; index++)
	{
		if(str[index] < '0' || str[index] > '9')
		{
			return 0U;
		}
	}
	return 1U;
}

static ClockSetResult_t ClockSetApply(const uint8_t *str, uint8_t length)
{
	uint16_t year;
	uint8_t month;
	uint8_t day;
	uint8_t hour;
	uint8_t minute;
	uint8_t second;
	RTC_DateTypeDef setdate = {0};
	RTC_TimeTypeDef settime = {0};
	RTC_DateTypeDef verifydate = {0};
	RTC_TimeTypeDef verifytime = {0};

	if(length != 20U || str[5] != '=')
	{
		return CLOCK_SET_BAD_LENGTH;
	}
	if(!AllDigits(str, 6U, 20U))
	{
		return CLOCK_SET_BAD_TIME;
	}

	year = (uint16_t)((str[6] - '0') * 1000U + (str[7] - '0') * 100U +
		(str[8] - '0') * 10U + (str[9] - '0'));
	month = ParseTwoDigits(str, 10U);
	day = ParseTwoDigits(str, 12U);
	hour = ParseTwoDigits(str, 14U);
	minute = ParseTwoDigits(str, 16U);
	second = ParseTwoDigits(str, 18U);

	if(year < 2000U || year > 2099U || month < 1U || month > 12U ||
		day < 1U || day > DaysInMonth(year, month) || hour > 23U ||
		minute > 59U || second > 59U)
	{
		return CLOCK_SET_BAD_TIME;
	}

	setdate.Year = (uint8_t)(year - 2000U);
	setdate.Month = month;
	setdate.Date = day;
	setdate.WeekDay = weekday_calculate(setdate.Year, month, day, 20);
	settime.Hours = hour;
	settime.Minutes = minute;
	settime.Seconds = second;
	settime.DayLightSaving = RTC_DAYLIGHTSAVING_NONE;
	settime.StoreOperation = RTC_STOREOPERATION_RESET;

	if(HAL_RTC_SetDate(&hrtc, &setdate, RTC_FORMAT_BIN) != HAL_OK ||
		HAL_RTC_SetTime(&hrtc, &settime, RTC_FORMAT_BIN) != HAL_OK)
	{
		return CLOCK_SET_RTC_ERROR;
	}

	HAL_RTC_GetTime(&hrtc, &verifytime, RTC_FORMAT_BIN);
	HAL_RTC_GetDate(&hrtc, &verifydate, RTC_FORMAT_BIN);
	if(verifydate.Year != setdate.Year || verifydate.Month != month ||
		verifydate.Date != day || verifytime.Hours != hour ||
		verifytime.Minutes != minute || verifytime.Seconds != second)
	{
		return CLOCK_SET_RTC_ERROR;
	}
	return CLOCK_SET_OK;
}

static uint8_t ParseUint32(const uint8_t *str, uint8_t length, uint32_t *value)
{
	uint8_t index;
	uint32_t parsed = 0U;
	if(length == 0U)
	{
		return 0U;
	}
	for(index = 0U; index < length; index++)
	{
		uint8_t digit;
		if(str[index] < '0' || str[index] > '9')
		{
			return 0U;
		}
		digit = (uint8_t)(str[index] - '0');
		if(parsed > 429496729U || (parsed == 429496729U && digit > 5U))
		{
			return 0U;
		}
		parsed = parsed * 10U + digit;
	}
	*value = parsed;
	return 1U;
}

void Stopwatch_Init(void)
{
	RTC_TimeTypeDef nowtime = {0};
	RTC_DateTypeDef nowdate = {0};
	uint32_t boot_counter;
	uint32_t rtc_value;
	uint32_t device_value;

	if(Stopwatch_Initialized)
	{
		return;
	}
	HAL_RTC_GetTime(&hrtc, &nowtime, RTC_FORMAT_BIN);
	HAL_RTC_GetDate(&hrtc, &nowdate, RTC_FORMAT_BIN);
	boot_counter = HAL_RTCEx_BKUPRead(&hrtc, STOPWATCH_BOOT_COUNTER_REGISTER) + 1U;
	if(boot_counter == 0U)
	{
		boot_counter = 1U;
	}
	HAL_RTCEx_BKUPWrite(&hrtc, STOPWATCH_BOOT_COUNTER_REGISTER, boot_counter);

	rtc_value = ((uint32_t)nowdate.Year << 25U) |
		((uint32_t)nowdate.Month << 21U) |
		((uint32_t)nowdate.Date << 16U) |
		((uint32_t)nowtime.Hours << 11U) |
		((uint32_t)nowtime.Minutes << 5U) |
		((uint32_t)nowtime.Seconds & 0x1FU);
	device_value = HAL_GetUIDw0() ^ RotateLeft32(HAL_GetUIDw1(), 7U) ^
		RotateLeft32(HAL_GetUIDw2(), 13U);
	Stopwatch_BootId = device_value ^ rtc_value ^ nowtime.SubSeconds ^
		(boot_counter * 2654435761UL);
	if(Stopwatch_BootId == 0U)
	{
		Stopwatch_BootId = boot_counter;
	}
	Stopwatch_Initialized = 1U;
}

void Stopwatch_Tick1ms(void)
{
	if(Stopwatch_State == STOPWATCH_STATE_RUNNING && Stopwatch_Elapsed < 0xFFFFFFFFU)
	{
		Stopwatch_Elapsed++;
	}
}

void Stopwatch_Start(void)
{
	Stopwatch_Init();
	taskENTER_CRITICAL();
	if(Stopwatch_State == STOPWATCH_STATE_IDLE)
	{
		Stopwatch_Elapsed = 0U;
		Stopwatch_ActiveSession = Stopwatch_NextSession++;
		if(Stopwatch_NextSession == 0U)
		{
			Stopwatch_NextSession = 1U;
		}
	}
	Stopwatch_State = STOPWATCH_STATE_RUNNING;
	taskEXIT_CRITICAL();
}

void Stopwatch_Pause(void)
{
	taskENTER_CRITICAL();
	if(Stopwatch_State == STOPWATCH_STATE_RUNNING)
	{
		Stopwatch_State = STOPWATCH_STATE_PAUSED;
	}
	taskEXIT_CRITICAL();
}

void Stopwatch_Finish(void)
{
	StopwatchLogRecord_t record = {0};
	uint8_t should_log = 0U;

	taskENTER_CRITICAL();
	if(Stopwatch_State != STOPWATCH_STATE_IDLE && Stopwatch_Elapsed > 0U)
	{
		record.session_id = Stopwatch_ActiveSession;
		record.duration_ms = Stopwatch_Elapsed;
		should_log = 1U;
	}
	Stopwatch_State = STOPWATCH_STATE_IDLE;
	Stopwatch_Elapsed = 0U;
	Stopwatch_ActiveSession = 0U;
	taskEXIT_CRITICAL();

	if(!should_log)
	{
		return;
	}
	taskENTER_CRITICAL();
	HAL_RTC_GetTime(&hrtc, &record.end_time, RTC_FORMAT_BIN);
	HAL_RTC_GetDate(&hrtc, &record.end_date, RTC_FORMAT_BIN);
	Stopwatch_Log[Stopwatch_LogWriteIndex] = record;
	Stopwatch_LogWriteIndex = (uint8_t)((Stopwatch_LogWriteIndex + 1U) % STOPWATCH_LOG_CAPACITY);
	if(Stopwatch_LogCount < STOPWATCH_LOG_CAPACITY)
	{
		Stopwatch_LogCount++;
	}
	taskEXIT_CRITICAL();
}

uint8_t Stopwatch_IsRunning(void)
{
	return (uint8_t)(Stopwatch_State == STOPWATCH_STATE_RUNNING);
}

uint32_t Stopwatch_ElapsedMs(void)
{
	return Stopwatch_Elapsed;
}

static const char *Stopwatch_StateName(StopwatchState_t state)
{
	switch(state)
	{
		case STOPWATCH_STATE_RUNNING:
			return "run";
		case STOPWATCH_STATE_PAUSED:
			return "pause";
		default:
			return "idle";
	}
}

static void Stopwatch_PrintStatus(void)
{
	StopwatchState_t state;
	uint32_t elapsed;
	uint32_t session_id;
	Stopwatch_Init();
	taskENTER_CRITICAL();
	state = Stopwatch_State;
	elapsed = Stopwatch_Elapsed;
	session_id = Stopwatch_ActiveSession;
	taskEXIT_CRITICAL();
	printf("OVSW|1|boot=%lu|sid=%lu|state=%s|elapsed_ms=%lu\r\n",
		(unsigned long)Stopwatch_BootId,
		(unsigned long)session_id,
		Stopwatch_StateName(state),
		(unsigned long)elapsed);
}

static uint8_t Stopwatch_FindLogAfter(uint32_t after, StopwatchLogRecord_t *record, uint8_t *more)
{
	uint8_t index;
	uint8_t oldest;
	uint8_t found = 0U;
	taskENTER_CRITICAL();
	oldest = (uint8_t)((Stopwatch_LogWriteIndex + STOPWATCH_LOG_CAPACITY - Stopwatch_LogCount) %
		STOPWATCH_LOG_CAPACITY);
	for(index = 0U; index < Stopwatch_LogCount; index++)
	{
		uint8_t slot = (uint8_t)((oldest + index) % STOPWATCH_LOG_CAPACITY);
		if(Stopwatch_Log[slot].session_id > after)
		{
			*record = Stopwatch_Log[slot];
			*more = (uint8_t)(index + 1U < Stopwatch_LogCount);
			found = 1U;
			break;
		}
	}
	taskEXIT_CRITICAL();
	return found;
}

static void Stopwatch_PrintLogAfter(uint32_t after)
{
	StopwatchLogRecord_t record;
	uint8_t more = 0U;
	Stopwatch_Init();
	if(!Stopwatch_FindLogAfter(after, &record, &more))
	{
		printf("OVSL|1|boot=%lu|none=1\r\n", (unsigned long)Stopwatch_BootId);
		return;
	}
	printf("OVSL|1|boot=%lu|sid=%lu|end=20%02d%02d%02dT%02d%02d%02d|dur_ms=%lu|more=%d\r\n",
		(unsigned long)Stopwatch_BootId,
		(unsigned long)record.session_id,
		record.end_date.Year,
		record.end_date.Month,
		record.end_date.Date,
		record.end_time.Hours,
		record.end_time.Minutes,
		record.end_time.Seconds,
		(unsigned long)record.duration_ms,
		more);
}

static void ClockSetPrintError(ClockSetResult_t result)
{
	const char *code = "RTC_ERROR";
	if(result == CLOCK_SET_BAD_LENGTH)
	{
		code = "INVALID_LENGTH";
	}
	else if(result == CLOCK_SET_BAD_TIME)
	{
		code = "INVALID_TIME";
	}
	printf("OVERR|1|cmd=ST|code=%s\r\n", code);
}


/**
  * @brief  send the message via BLE, use uart
  * @param  argument: Not used
  * @retval None
  */
void MessageSendTask(void *argument)
{
	while(1)
	{
		uint32_t hardint_flags = osEventFlagsWait(HardIntEventHandle, HARDINT_EVENT_UART, osFlagsWaitAny, osWaitForever);
		if((hardint_flags & HARDINT_EVENT_UART) != 0U)
		{
			uint8_t IdleBreakstr = 0;
			uint8_t command_length = CommandLength(HardInt_receive_str);
			osMessageQueuePut(IdleBreak_MessageQueue,&IdleBreakstr,NULL,1);
			printf("RecStr:%.*s\r\n", (int)command_length, (char *)HardInt_receive_str);
			if(CommandEquals(HardInt_receive_str, command_length, "OV"))
			{
				printf("OK\r\n");
			}
			else if(CommandEquals(HardInt_receive_str, command_length, "OV+VERSION"))
			{
				printf("VERSION=V%d.%d.%d\r\n", VERSION_MAJOR, VERSION_MINOR, VERSION_PATCH);
			}
			else if(CommandEquals(HardInt_receive_str, command_length, "OV+SEND"))
			{
				HAL_RTC_GetTime(&hrtc,&(BLEMessage.nowtime),RTC_FORMAT_BIN);
				HAL_RTC_GetDate(&hrtc,&BLEMessage.nowdate,RTC_FORMAT_BIN);
				BLEMessage.humi = HWInterface.AHT21.humidity;
				BLEMessage.temp = HWInterface.AHT21.temperature;
				BLEMessage.HR = HWInterface.HR_meter.HrRate;
				BLEMessage.SPO2 = HWInterface.HR_meter.SPO2;
				BLEMessage.stepNum = HWInterface.IMU.Steps;

				printf("data:%2d-%02d\r\n",BLEMessage.nowdate.Month,BLEMessage.nowdate.Date);
				printf("time:%02d:%02d:%02d\r\n",BLEMessage.nowtime.Hours,BLEMessage.nowtime.Minutes,BLEMessage.nowtime.Seconds);
				printf("humidity:%d%%\r\n",BLEMessage.humi);
				printf("temperature:%d\r\n",BLEMessage.temp);
				printf("Heart Rate:%d%%\r\n",BLEMessage.HR);
				printf("SPO2:%d%%\r\n",BLEMessage.SPO2);
				printf("Step today:%d\r\n",BLEMessage.stepNum);
			}
			else if(CommandEquals(HardInt_receive_str, command_length, "OV+DATA"))
			{
				HAL_RTC_GetTime(&hrtc,&(BLEMessage.nowtime),RTC_FORMAT_BIN);
				HAL_RTC_GetDate(&hrtc,&BLEMessage.nowdate,RTC_FORMAT_BIN);
				BLEMessage.humi = HWInterface.AHT21.humidity;
				BLEMessage.temp = HWInterface.AHT21.temperature;
				BLEMessage.HR = HWInterface.HR_meter.HrRate;
				BLEMessage.stepNum = HWInterface.IMU.Steps;

				/*
				 * OVD v1 is a single CRLF-terminated telemetry frame. Keep SpO2
				 * unavailable until the firmware has a real measurement path.
				 */
				printf("OVD|1|ts=20%02d%02d%02dT%02d%02d%02d|temp=%d|humi=%d|hr=%d|spo2=na|steps=%d\r\n",
					BLEMessage.nowdate.Year,
					BLEMessage.nowdate.Month,
					BLEMessage.nowdate.Date,
					BLEMessage.nowtime.Hours,
					BLEMessage.nowtime.Minutes,
					BLEMessage.nowtime.Seconds,
					BLEMessage.temp,
					BLEMessage.humi,
					BLEMessage.HR,
					BLEMessage.stepNum);
			}
			else if(CommandEquals(HardInt_receive_str, command_length, "OV+CAP"))
			{
				printf("OVCAP|1|data=1|clock=1|clock_sync=%d|sw=1|swlog=1|swlog_cap=%d|persist=0\r\n",
					ui_APPSy_EN ? 1 : 0,
					STOPWATCH_LOG_CAPACITY);
			}
			else if(CommandEquals(HardInt_receive_str, command_length, "OV+SW"))
			{
				Stopwatch_PrintStatus();
			}
			else if(CommandStartsWith(HardInt_receive_str, command_length, "OV+SWLOG="))
			{
				uint32_t after;
				if(ParseUint32(&HardInt_receive_str[9], (uint8_t)(command_length - 9U), &after))
				{
					Stopwatch_PrintLogAfter(after);
				}
				else
				{
					printf("OVERR|1|cmd=SWLOG|code=INVALID_AFTER\r\n");
				}
			}
			//set time//OV+ST=20230629125555
			else if(CommandStartsWith(HardInt_receive_str, command_length, "OV+ST"))
			{
				ClockSetResult_t result;
				if(command_length != 20U || HardInt_receive_str[5] != '=')
				{
					printf("OVERR|1|cmd=ST|code=INVALID_LENGTH\r\n");
				}
				else if(!ui_APPSy_EN)
				{
					printf("OVERR|1|cmd=ST|code=SYNC_DISABLED\r\n");
				}
				else
				{
					result = ClockSetApply(HardInt_receive_str, command_length);
					if(result == CLOCK_SET_OK)
					{
						printf("TIMESETOK\r\n");
					}
					else
					{
						ClockSetPrintError(result);
					}
				}
			}
			memset(HardInt_receive_str,0,sizeof(HardInt_receive_str));
		}
	}
}


