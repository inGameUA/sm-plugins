#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include "morecolors.inc"
#undef REQUIRE_PLUGIN

#pragma newdecls required
#define PLUGIN_VERSION 	"1.3.0"

bool g_bStopSound[MAXPLAYERS+1];
bool g_bHooked;
static char g_sKVPATH[PLATFORM_MAX_PATH];
KeyValues g_hWepSounds;

public Plugin myinfo =
{
	name = "Toggle Weapon Sounds",
	author = "GoD-Tony, edit by Obus + BotoX",
	description = "Allows clients to stop hearing weapon sounds",
	version = PLUGIN_VERSION,
	url = "http://www.sourcemod.net/"
};

public void OnPluginStart()
{
	// Detect game and hook appropriate tempent.
	static char sGame[32];
	GetGameFolderName(sGame, sizeof(sGame));

	if(StrEqual(sGame, "cstrike"))
		AddTempEntHook("Shotgun Shot", CSS_Hook_ShotgunShot);
	else if(StrEqual(sGame, "dod"))
		AddTempEntHook("FireBullets", DODS_Hook_FireBullets);

	// TF2/HL2:DM and misc weapon sounds will be caught here.
	AddNormalSoundHook(Hook_NormalSound);

	CreateConVar("sm_stopsound_version", PLUGIN_VERSION, "Toggle Weapon Sounds", FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_REPLICATED);
	RegConsoleCmd("sm_stopsound", Command_StopSound, "Toggle hearing weapon sounds");

	g_hWepSounds = new KeyValues("WeaponSounds");
	BuildPath(Path_SM, g_sKVPATH, sizeof(g_sKVPATH), "data/playerprefs.WepSounds.txt");
	g_hWepSounds.ImportFromFile(g_sKVPATH);

	// Suppress reload sound effects
	UserMsg ReloadEffect = GetUserMessageId("ReloadEffect");
	if(ReloadEffect != INVALID_MESSAGE_ID)
		HookUserMessage(ReloadEffect, Hook_ReloadEffect, true);

	// Late load
	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client) && IsClientAuthorized(client))
		{
			static char sAuth[32];
			GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth));
			OnClientAuthorized(client, sAuth);
		}
	}
}

public void OnPluginEnd()
{
	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client))
			OnClientDisconnect_Post(client);
	}

	// Detect game and unhook appropriate tempent.
	static char sGame[32];
	GetGameFolderName(sGame, sizeof(sGame));

	if(StrEqual(sGame, "cstrike"))
		RemoveTempEntHook("Shotgun Shot", CSS_Hook_ShotgunShot);
	else if(StrEqual(sGame, "dod"))
		RemoveTempEntHook("FireBullets", DODS_Hook_FireBullets);

	// TF2/HL2:DM and misc weapon sounds were caught here.
	RemoveNormalSoundHook(Hook_NormalSound);

	UserMsg ReloadEffect = GetUserMessageId("ReloadEffect");
	if(ReloadEffect != INVALID_MESSAGE_ID)
		UnhookUserMessage(ReloadEffect, Hook_ReloadEffect, true);
}

public Action Command_StopSound(int client, int args)
{
	if(client == 0)
	{
		PrintToServer("[SM] Cannot use command from server console.");
		return Plugin_Handled;
	}

	if(args > 0)
	{
		static char Arguments[32];
		GetCmdArg(1, Arguments, sizeof(Arguments));

		static char SID[32];
		GetClientAuthId(client, AuthId_Steam2, SID, sizeof(SID));

		if(StrEqual(Arguments, "save"))
		{
			g_hWepSounds.Rewind();

			if(g_hWepSounds.JumpToKey(SID, true))
			{
				int disabled = g_hWepSounds.GetNum("disabled", 0);
				if(!disabled)
				{
					//CPrintToChat(client, "[StopSound] Saved entry for STEAMID({green}%s{default}) {green}successfully{default}.", SID);
					g_hWepSounds.SetNum("disabled", 1);
					g_hWepSounds.Rewind();
					g_hWepSounds.ExportToFile(g_sKVPATH);

					g_bStopSound[client] = true;
					CReplyToCommand(client, "{green}[StopSound]{default} Weapon sounds {red}disabled{default} - {green}entry saved{default}.");
					CheckHooks();

					return Plugin_Handled;
				}
				else
				{
					//CPrintToChat(client, "[StopSound] Entry for STEAMID({green}%s{default}) {green}successfully deleted{default}.", SID);
					g_hWepSounds.DeleteThis();
					g_hWepSounds.Rewind();
					g_hWepSounds.ExportToFile(g_sKVPATH);

					g_bStopSound[client] = false;
					CReplyToCommand(client, "{green}[StopSound]{default} Weapon sounds {green}enabled{default} - {red}entry deleted{default}.");
					CheckHooks();

					return Plugin_Handled;
				}
			}

			g_hWepSounds.Rewind();
		}
		else if(StrEqual(Arguments, "delete"))
		{
			g_hWepSounds.Rewind();

			if(g_hWepSounds.JumpToKey(SID, false))
			{
				g_bStopSound[client] = false;
				CReplyToCommand(client, "{green}[StopSound]{default} Weapon sounds {green}enabled{default} - {red}entry deleted{default}.");
				CheckHooks();

				g_hWepSounds.DeleteThis();
				g_hWepSounds.Rewind();
				g_hWepSounds.ExportToFile(g_sKVPATH);

				return Plugin_Handled;
			}
			else
			{
				CPrintToChat(client, "{green}[StopSound]{default} Entry {red}not found{default}.");
				return Plugin_Handled;
			}
		}
		else
		{
			PrintToChat(client, "[SM] Usage sm_stopsound <save|delete>");
			return Plugin_Handled;
		}
	}

	g_bStopSound[client] = !g_bStopSound[client];
	CReplyToCommand(client, "{green}[StopSound]{default} Weapon sounds %s.", g_bStopSound[client] ? "{red}disabled{default}" : "{green}enabled{default}");
	CheckHooks();

	return Plugin_Handled;
}

public void OnClientAuthorized(int client, const char[] auth)
{
	g_hWepSounds.Rewind();

	if(KvJumpToKey(g_hWepSounds, auth, false))
	{
		int disabled = g_hWepSounds.GetNum("disabled", 0);
		if(disabled)
			g_bStopSound[client] = true;
	}

	CheckHooks();
	g_hWepSounds.Rewind();
}

public void OnClientDisconnect_Post(int client)
{
	g_bStopSound[client] = false;
	CheckHooks();
}

void CheckHooks()
{
	bool bShouldHook = false;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(g_bStopSound[i])
		{
			bShouldHook = true;
			break;
		}
	}

	// Fake (un)hook because toggling actual hooks will cause server instability.
	g_bHooked = bShouldHook;
}

public Action Hook_NormalSound(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH],
	  int &entity, int &channel, float &volume, int &level, int &pitch, int &flags,
	  char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	// Ignore non-weapon sounds.
	if(!g_bHooked || !(strncmp(sample, "weapons", 7) == 0 || strncmp(sample[1], "weapons", 7) == 0))
		return Plugin_Continue;

	for(int i = 0; i < numClients; i++)
	{
		int client = clients[i];
		if(g_bStopSound[client])
		{
			// Remove the client from the array.
			for(int j = i; j < numClients - 1; j++)
				clients[j] = clients[j + 1];

			numClients--;
			i--;
		}
	}

	return (numClients > 0) ? Plugin_Changed : Plugin_Stop;
}

public Action CSS_Hook_ShotgunShot(const char[] te_name, const int[] Players, int numClients, float delay)
{
	if(!g_bHooked)
		return Plugin_Continue;

	// Check which clients need to be excluded.
	int[] newClients = new int[numClients];
	int newTotal = 0;

	for(int i = 0; i < numClients; i++)
	{
		int client = Players[i];
		if(!g_bStopSound[client])
			newClients[newTotal++] = client;
	}

	// No clients were excluded.
	if(newTotal == numClients)
		return Plugin_Continue;
	else if(newTotal == 0) // All clients were excluded and there is no need to broadcast.
		return Plugin_Stop;

	// Re-broadcast to clients that still need it.
	float vTemp[3];
	TE_Start("Shotgun Shot");
	TE_ReadVector("m_vecOrigin", vTemp);
	TE_WriteVector("m_vecOrigin", vTemp);
	TE_WriteFloat("m_vecAngles[0]", TE_ReadFloat("m_vecAngles[0]"));
	TE_WriteFloat("m_vecAngles[1]", TE_ReadFloat("m_vecAngles[1]"));
	TE_WriteNum("m_iWeaponID", TE_ReadNum("m_iWeaponID"));
	TE_WriteNum("m_iMode", TE_ReadNum("m_iMode"));
	TE_WriteNum("m_iSeed", TE_ReadNum("m_iSeed"));
	TE_WriteNum("m_iPlayer", TE_ReadNum("m_iPlayer"));
	TE_WriteFloat("m_fInaccuracy", TE_ReadFloat("m_fInaccuracy"));
	TE_WriteFloat("m_fSpread", TE_ReadFloat("m_fSpread"));
	TE_Send(newClients, newTotal, delay);

	return Plugin_Stop;
}

public Action DODS_Hook_FireBullets(const char[] te_name, const int[] Players, int numClients, float delay)
{
	if(!g_bHooked)
		return Plugin_Continue;

	// Check which clients need to be excluded.
	int[] newClients = new int[numClients];
	int newTotal = 0;

	for(int i = 0; i < numClients; i++)
	{
		int client = Players[i];
		if(!g_bStopSound[client])
			newClients[newTotal++] = client;
	}

	// No clients were excluded.
	if(newTotal == numClients)
		return Plugin_Continue;
	else if(newTotal == 0)// All clients were excluded and there is no need to broadcast.
		return Plugin_Stop;

	// Re-broadcast to clients that still need it.
	float vTemp[3];
	TE_Start("FireBullets");
	TE_ReadVector("m_vecOrigin", vTemp);
	TE_WriteVector("m_vecOrigin", vTemp);
	TE_WriteFloat("m_vecAngles[0]", TE_ReadFloat("m_vecAngles[0]"));
	TE_WriteFloat("m_vecAngles[1]", TE_ReadFloat("m_vecAngles[1]"));
	TE_WriteNum("m_iWeaponID", TE_ReadNum("m_iWeaponID"));
	TE_WriteNum("m_iMode", TE_ReadNum("m_iMode"));
	TE_WriteNum("m_iSeed", TE_ReadNum("m_iSeed"));
	TE_WriteNum("m_iPlayer", TE_ReadNum("m_iPlayer"));
	TE_WriteFloat("m_flSpread", TE_ReadFloat("m_flSpread"));
	TE_Send(newClients, newTotal, delay);

	return Plugin_Stop;
}

public Action Hook_ReloadEffect(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if(!g_bHooked)
		return Plugin_Continue;

	int client = msg.ReadShort();

	// Check which clients need to be excluded.
	int[] newClients = new int[playersNum];
	int newTotal = 0;

	for(int i = 0; i < playersNum; i++)
	{
		int client_ = players[i];
		if(IsClientInGame(client_) && !g_bStopSound[client_])
			newClients[newTotal++] = client_;
	}

	// No clients were excluded.
	if(newTotal == playersNum)
		return Plugin_Continue;
	else if(newTotal == 0) // All clients were excluded and there is no need to broadcast.
		return Plugin_Handled;

	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteCell(newTotal);

	for(int i = 0; i < newTotal; i++)
		pack.WriteCell(newClients[i]);

	RequestFrame(OnReloadEffect, pack);

	return Plugin_Handled;
}

public void OnReloadEffect(DataPack pack)
{
	pack.Reset();
	int client = pack.ReadCell();
	int newTotal = pack.ReadCell();

	int[] players = new int[newTotal];
	int playersNum = 0;

	for(int i = 0; i < newTotal; i++)
	{
		int client_ = pack.ReadCell();
		if(IsClientInGame(client_))
			players[playersNum++] = client_;
	}
	CloseHandle(pack);

	Handle ReloadEffect = StartMessage("ReloadEffect", players, playersNum, USERMSG_RELIABLE | USERMSG_BLOCKHOOKS);
	if(GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf)
		PbSetInt(ReloadEffect, "entidx", client);
	else
		BfWriteShort(ReloadEffect, client);
	EndMessage();
}
