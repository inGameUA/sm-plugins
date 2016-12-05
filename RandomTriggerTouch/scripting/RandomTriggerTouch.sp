#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <CSSFixes>

#pragma semicolon 1
#pragma newdecls required

Handle g_hCBaseEntity_Touch;
bool g_bIgnoreHook = false;

#define TOUCHED_MAX (MAXPLAYERS + 1)
int g_aTouched[TOUCHED_MAX];
int g_aaTouchedList[TOUCHED_MAX][MAXPLAYERS + 1];
int g_aTouchedListSize[TOUCHED_MAX];

public Plugin myinfo =
{
	name = "Randomize Trigger Touch",
	author = "BotoX",
	description = "Randomize Touches on trigger_multiple",
	version = "1.0"
}

public void OnPluginStart()
{
	Handle hGameConf = LoadGameConfigFile("sdkhooks.games");
	if(hGameConf == INVALID_HANDLE)
	{
		SetFailState("Couldn't load sdkhooks.games game config!");
		return;
	}

	if(GameConfGetOffset(hGameConf, "Touch") == -1)
	{
		CloseHandle(hGameConf);
		SetFailState("Couldn't get Touch offset from game config!");
		return;
	}

	// void CBaseEntity::Touch( CBaseEntity *pOther )
	StartPrepSDKCall(SDKCall_Entity);
	if(!PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "Touch"))
	{
		CloseHandle(hGameConf);
		SetFailState("PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, \"Touch\" failed!");
		return;
	}
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	g_hCBaseEntity_Touch = EndPrepSDKCall();

	// Late load
	int entity = INVALID_ENT_REFERENCE;
	while((entity = FindEntityByClassname(entity, "trigger_multiple")) != INVALID_ENT_REFERENCE)
	{
		SDKHook(entity, SDKHook_Touch, OnTouch);
	}
}

public void OnRunThinkFunctionsPost(bool simulating)
{
	g_bIgnoreHook = true;
	for(int i = 0; i < sizeof(g_aTouched); i++)
	{
		if(!g_aTouched[i])
			break;

		if(!IsValidEntity(g_aTouched[i]))
			continue;

		// Fisher-Yates Shuffle
		for(int j = g_aTouchedListSize[i] - 1; j >= 1; j--)
		{
			int k = GetRandomInt(0, j);
			int t = g_aaTouchedList[i][j];
			g_aaTouchedList[i][j] = g_aaTouchedList[i][k];
			g_aaTouchedList[i][k] = t;
		}

		for(int j = 0; j < g_aTouchedListSize[i]; j++)
		{
			if(IsValidEntity(g_aaTouchedList[i][j]))
				SDKCall(g_hCBaseEntity_Touch, g_aTouched[i], g_aaTouchedList[i][j]);
		}

		g_aTouched[i] = 0;
		g_aTouchedListSize[i] = 0;
	}
	g_bIgnoreHook = false;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "trigger_multiple"))
	{
		SDKHook(entity, SDKHook_Touch, OnTouch);
	}
}

public Action OnTouch(int touched, int toucher)
{
	if(toucher > MAXPLAYERS || g_bIgnoreHook)
		return Plugin_Continue;

	int i;
	for(i = 0; i < sizeof(g_aTouched); i++)
	{
		if(!g_aTouched[i] || g_aTouched[i] == touched)
			break;
	}

	if(i == sizeof(g_aTouched))
		return Plugin_Continue;

	g_aTouched[i] = touched;

	for(int j = 0; j < g_aTouchedListSize[i]; j++)
	{
		if(g_aaTouchedList[i][j] == toucher)
			return Plugin_Handled;
	}

	g_aaTouchedList[i][g_aTouchedListSize[i]++] = toucher;

	return Plugin_Handled;
}

stock int GetHighestClientIndex()
{
	for(int i = MaxClients; i >= 1; i--)
	{
		if(IsValidEntity(i))
			return i;
	}
	return 0;
}
