#ifndef __USER_MESSAGESENDTASK_H__
#define __USER_MESSAGESENDTASK_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "stdint.h"

#define STOPWATCH_LOG_CAPACITY 8U

typedef enum
{
	STOPWATCH_STATE_IDLE = 0,
	STOPWATCH_STATE_RUNNING,
	STOPWATCH_STATE_PAUSED
} StopwatchState_t;

void MessageSendTask(void *argument);

void Stopwatch_Init(void);
void Stopwatch_Tick1ms(void);
void Stopwatch_Start(void);
void Stopwatch_Pause(void);
void Stopwatch_Finish(void);
uint8_t Stopwatch_IsRunning(void);
uint32_t Stopwatch_ElapsedMs(void);


#ifdef __cplusplus
}
#endif

#endif

