#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

#pragma newdecls required

public Plugin myinfo =
{
	name		= "Teleport Commands",
	author		= "Obus",
	description	= "Adds commands to teleport players.",
	version		= "1.0",
	url			= ""
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");

	RegAdminCmd("sm_bring", Command_Bring, ADMFLAG_GENERIC, "Brings a player to your position.");
	RegAdminCmd("sm_goto", Command_Goto, ADMFLAG_GENERIC, "Teleports you to a player.");
	RegAdminCmd("sm_send", Command_Send, ADMFLAG_GENERIC, "Sends a player to another player.");
	RegAdminCmd("sm_tpaim", Command_TpAim, ADMFLAG_GENERIC, "Teleports a player to your crosshair.");
}

public Action Command_Bring(int client, int argc)
{
	if (!client)
	{
		PrintToServer("[SM] Cannot use command from server console.");
		return Plugin_Handled;
	}

	if (argc < 1)
	{
		PrintToChat(client, "[SM] Usage: sm_bring <name|#userid>");
		return Plugin_Handled;
	}

	float vecClientPos[3];
	char sArgs[64];
	char sTargetName[MAX_TARGET_LENGTH];
	int iTargets[MAXPLAYERS];
	int iTargetCount;
	bool bIsML;

	GetCmdArg(1, sArgs, sizeof(sArgs));
	GetClientAbsOrigin(client, vecClientPos);

	if ((iTargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS, COMMAND_FILTER_ALIVE, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}

	for (int i = 0; i < iTargetCount; i++)
	{
		TeleportEntity(iTargets[i], vecClientPos, NULL_VECTOR, NULL_VECTOR);
	}

	PrintToChatAll("\x01[SM] \x04%N\x01: Brought \x04%s\x01.", client, sTargetName);

	return Plugin_Handled;
}

public Action Command_Goto(int client, int argc)
{
	if (!client)
	{
		PrintToServer("[SM] Cannot use command from server console.");
		return Plugin_Handled;
	}

	if (argc < 1)
	{
		PrintToChat(client, "[SM] Usage: sm_goto <name|#userid|@aim>");
		return Plugin_Handled;
	}

	int iTarget;
	char sTarget[32];

	GetCmdArg(1, sTarget, sizeof(sTarget));

	if (!strcmp(sTarget, "@aim"))
	{
		if (argc > 1)
		{
			char sOption[2];

			GetCmdArg(2, sOption, sizeof(sOption));

			if (StringToInt(sOption) <= 0)
			{
				float vecEndPos[3];

				if (!TracePlayerAngles(client, vecEndPos))
				{
					PrintToChat(client, "[SM] Couldn't perform trace to your crosshair.");
					return Plugin_Handled;
				}

				TeleportEntity(client, vecEndPos, NULL_VECTOR, NULL_VECTOR);
				PrintToChatAll("\x01[SM] \x04%N\x01: Teleported to their crosshair.", client);

				return Plugin_Handled;
			}
		}

		int AimTarget = GetClientAimTarget(client, true);

		if (AimTarget == -1)
		{
			float vecEndPos[3];

			if (!TracePlayerAngles(client, vecEndPos))
			{
				PrintToChat(client, "[SM] Couldn't perform trace to your crosshair.");
				return Plugin_Handled;
			}

			TeleportEntity(client, vecEndPos, NULL_VECTOR, NULL_VECTOR);
			PrintToChatAll("\x01[SM] \x04%N\x01: Teleported to their crosshair.", client);

			return Plugin_Handled;
		}
	}

	if (!(iTarget = FindTarget(client, sTarget)))
		return Plugin_Handled;

	float vecTargetPos[3];

	GetClientAbsOrigin(iTarget, vecTargetPos);

	TeleportEntity(client, vecTargetPos, NULL_VECTOR, NULL_VECTOR);

	PrintToChatAll("\x01[SM] \x04%N\x01: Teleported to \x04%N\x01.", client, iTarget);

	return Plugin_Handled;
}

public Action Command_Send(int client, int argc)
{
	if (argc < 2)
	{
		PrintToChat(client, "[SM] Usage: sm_send <name|#userid> <name|#userid>");
		return Plugin_Handled;
	}

	float vecTargetPos[3];
	int iTarget;
	char sArgs[32];
	char sTarget[32];
	char sTargetName[MAX_TARGET_LENGTH];
	int iTargets[MAXPLAYERS];
	int iTargetCount;
	bool bIsML;

	GetCmdArg(1, sArgs, sizeof(sArgs));
	GetCmdArg(2, sTarget, sizeof(sTarget));

	if ((iTargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS, COMMAND_FILTER_ALIVE, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}

	if (!strcmp(sTarget, "@aim"))
	{
		if (!client)
		{
			ReplyToCommand(client, "[SM] Cannot use @aim from server console.");
			return Plugin_Handled;
		}

		float vecEndPos[3];

		if (!TracePlayerAngles(client, vecEndPos))
		{
			PrintToChat(client, "[SM] Couldn't perform trace to your crosshair.");
			return Plugin_Handled;
		}

		for (int i = 0; i < iTargetCount; i++)
		{
			TeleportEntity(iTargets[i], vecEndPos, NULL_VECTOR, NULL_VECTOR);
		}

		PrintToChatAll("\x01[SM] \x04%N\x01: Teleported \x04%s\x01 to their crosshair.", client, sTargetName);

		return Plugin_Handled;
	}

	if (!(iTarget = FindTarget(client, sTarget)))
		return Plugin_Handled;

	GetClientAbsOrigin(iTarget, vecTargetPos);

	for (int i = 0; i < iTargetCount; i++)
	{
		TeleportEntity(iTargets[i], vecTargetPos, NULL_VECTOR, NULL_VECTOR);
	}

	PrintToChatAll("\x01[SM] \x04%N\x01: Teleported \x04%s\x01 to \x04%N\x01.", client, sTargetName, iTarget);

	return Plugin_Handled;
}

public Action Command_TpAim(int client, int argc)
{
	if (!client)
	{
		PrintToServer("[SM] Cannot use command from server console.");
		return Plugin_Handled;
	}

	float vecEndPos[3];
	char sArgs[32];
	char sTargetName[MAX_TARGET_LENGTH];
	int iTargets[MAXPLAYERS];
	int iTargetCount;
	bool bIsML;

	GetCmdArg(1, sArgs, sizeof(sArgs));

	if ((iTargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS, COMMAND_FILTER_ALIVE, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}

	TracePlayerAngles(client, vecEndPos);

	for (int i = 0; i < iTargetCount; i++)
	{
		TeleportEntity(iTargets[i], vecEndPos, NULL_VECTOR, NULL_VECTOR);
	}

	PrintToChatAll("\x01[SM] \x04%N\x01: Teleported \x04%s\x01 to their crosshair.", client, sTargetName);

	return Plugin_Handled;
}

bool TracePlayerAngles(int client, float vecResult[3])
{
	if (!IsClientInGame(client))
		return false;

	float vecEyeAngles[3];
	float vecEyeOrigin[3];

	GetClientEyeAngles(client, vecEyeAngles);
	GetClientEyePosition(client, vecEyeOrigin);

	Handle hTraceRay = TR_TraceRayFilterEx(vecEyeOrigin, vecEyeAngles, MASK_SHOT_HULL, RayType_Infinite, FilterPlayers);

	if (TR_DidHit(hTraceRay))
	{
		TR_GetEndPosition(vecResult, hTraceRay);
		CloseHandle(hTraceRay);

		return true;
	}

	CloseHandle(hTraceRay);

	return false;
}

stock bool FilterPlayers(int entity, int contentsMask)
{
	return entity > MaxClients;
}
