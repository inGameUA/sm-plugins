#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>

#pragma newdecls required

bool g_bInBuyZoneAll = false;
bool g_bInBuyZone[MAXPLAYERS + 1] = {false, ...};

bool g_bInfAmmoHooked = false;
bool g_bInfAmmoAll = false;
bool g_bInfAmmo[MAXPLAYERS + 1] = {false, ...};

ConVar g_CVar_sv_pausable;
ConVar g_CVar_sv_bombanywhere;

static char g_sServerCanExecuteCmds[][] = {	"cl_soundscape_flush", "r_screenoverlay", "playgamesound",
						"slot0", "slot1", "slot2", "slot3", "slot4", "slot5", "slot6",
						"slot7", "slot8", "slot9", "slot10", "cl_spec_mode", "cancelselect",
						"invnext", "play", "invprev", "sndplaydelay", "lastinv", "dsp_player",
						"name", "redirect", "retry", "r_cleardecals", "echo", "soundfade"	};

public Plugin myinfo =
{
	name 		= "Advanced Commands",
	author 		= "BotoX + Obus",
	description	= "Adds extra commands for admins.",
	version 	= "2.1.0",
	url 		= "https://github.com/CSSZombieEscape/sm-plugins/tree/master/ExtraCommands/"
};
 
public void OnPluginStart()
{
	LoadTranslations("common.phrases");

	RegAdminCmd("sm_hp", Command_Health, ADMFLAG_GENERIC, "sm_hp <#userid|name> <value>");
	RegAdminCmd("sm_health", Command_Health, ADMFLAG_GENERIC, "sm_health <#userid|name> <value>");
	RegAdminCmd("sm_armor", Command_Armor, ADMFLAG_GENERIC, "sm_armor <#userid|name> <value>");
	RegAdminCmd("sm_weapon", Command_Weapon, ADMFLAG_GENERIC, "sm_weapon <#userid|name> <name> [clip] [ammo]");
	RegAdminCmd("sm_give", Command_Weapon, ADMFLAG_GENERIC, "sm_give <#userid|name> <name> [clip] [ammo]");
	RegAdminCmd("sm_strip", Command_Strip, ADMFLAG_GENERIC, "sm_strip <#userid|name>");
	RegAdminCmd("sm_buyzone", Command_BuyZone, ADMFLAG_GENERIC, "sm_buyzone <#userid|name> <0|1>");
	RegAdminCmd("sm_iammo", Command_InfAmmo, ADMFLAG_GENERIC, "sm_iammo <#userid|name> <0|1>");
	RegAdminCmd("sm_speed", Command_Speed, ADMFLAG_GENERIC, "sm_speed <#userid|name> <0|1>");
	RegAdminCmd("sm_respawn", Command_Respawn, ADMFLAG_GENERIC, "sm_respawn <#userid|name>");
	RegAdminCmd("sm_cash", Command_Cash, ADMFLAG_GENERIC, "sm_cash <#userid|name> <value>");
	RegAdminCmd("sm_modelscale", Command_ModelScale, ADMFLAG_GENERIC, "sm_modelscale <#userid|name> <scale>");
	RegAdminCmd("sm_resize", Command_ModelScale, ADMFLAG_GENERIC, "sm_resize <#userid|name> <scale>");
	RegAdminCmd("sm_setmodel", Command_SetModel, ADMFLAG_GENERIC, "sm_setmodel <#userid|name> <modelpath>");
	RegAdminCmd("sm_setscore", Command_SetScore, ADMFLAG_GENERIC, "sm_setscore <#userid|name> <value>");
	RegAdminCmd("sm_setdeath", Command_SetDeath, ADMFLAG_GENERIC, "sm_setdeath <#userid|name> <value>");
	RegAdminCmd("sm_setteamscore", Command_SetTeamScore, ADMFLAG_GENERIC, "sm_setteamscore <team> <value>");
	RegAdminCmd("sm_waila", Command_WAILA, ADMFLAG_GENERIC);
	RegAdminCmd("sm_info", Command_WAILA, ADMFLAG_GENERIC);
	RegAdminCmd("sm_fcvar", Command_ForceCVar, ADMFLAG_CHEATS, "sm_fcvar <#userid|name> <cvar> <value>");
	RegAdminCmd("sm_setclantag", Command_SetClanTag, ADMFLAG_CHEATS, "sm_setclantag <#userid|name> [text]");
	RegAdminCmd("sm_fakecommand", Command_FakeCommand, ADMFLAG_CHEATS, "sm_fakecommand <#userid|name> [command] [args]");

	HookEvent("bomb_planted", Event_BombPlanted, EventHookMode_Pre);
	HookEvent("bomb_defused", Event_BombDefused, EventHookMode_Pre);

	g_CVar_sv_pausable = FindConVar("sv_pausable");
	g_CVar_sv_bombanywhere = CreateConVar("sv_bombanywhere", "0", "Allows the bomb to be planted anywhere", FCVAR_NOTIFY);

	AutoExecConfig(true, "plugin.extracommands");

	if(g_CVar_sv_pausable)
	{
		AddCommandListener(Listener_Pause, "pause");
		AddCommandListener(Listener_Pause, "setpause"); //doesn't work on win32 srcds?
		AddCommandListener(Listener_Pause, "unpause"); //doesn't work on win32 srcds?
	}
}

public void OnMapStart()
{
	g_bInBuyZoneAll = false;
	g_bInfAmmoAll = false;

	if(g_bInfAmmoHooked)
	{
		UnhookEvent("weapon_fire", Event_WeaponFire);
		g_bInfAmmoHooked = false;
	}

	/* Handle late load */
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientConnected(i) && IsClientInGame(i))
		{
			g_bInfAmmo[i] = false;
			g_bInBuyZone[i] = false;
			SDKHook(i, SDKHook_PreThink, OnPreThink);
			SDKHook(i, SDKHook_PostThinkPost, OnPostThinkPost);
		}
	}
}

public Action Listener_Pause(int client, const char[] command, int argc)
{
	static bool bPaused;

	if(!g_CVar_sv_pausable.BoolValue)
	{
		ReplyToCommand(client, "[SM] \"sv_pausable\" is set to 0!");
		return Plugin_Handled;
	}

	if(client == 0)
	{
		PrintToServer("[SM] Cannot use command from server console.");
		return Plugin_Handled;
	}

	if(!IsClientAuthorized(client) || !GetAdminFlag(GetUserAdmin(client), Admin_Generic))
	{
		ReplyToCommand(client, "[SM] You do not have permission to pause/unpause the game.");
		return Plugin_Handled;
	}

	if(strcmp(command, "setpause") == 0)
		bPaused = true;
	else if(strcmp(command, "unpause") == 0)
		bPaused = false;
	else
		bPaused = !bPaused;

	ShowActivity2(client, "\x01[SM] \x04", "%s\x01 the game.", bPaused ? "Paused" : "Unpaused");
	LogAction(client, -1, "\"%L\" %s the game.", client, bPaused ? "Paused" : "Unpaused");

	return Plugin_Continue;
}


public Action Event_BombPlanted(Handle event, const char[] name, bool dontBroadcast)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
			ClientCommand(i, "playgamesound \"radio/bombpl.wav\"");
	}
	return Plugin_Handled;
}

public Action Event_BombDefused(Handle event, const char[] name, bool dontBroadcast)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
			ClientCommand(i, "playgamesound \"radio/bombdef.wav\"");
	}
	return Plugin_Handled;
}

public void OnClientPutInServer(int client)
{
	g_bInBuyZone[client] = false;
	g_bInfAmmo[client] = false;

	SDKHook(client, SDKHook_PreThink, OnPreThink);
	SDKHook(client, SDKHook_PostThinkPost, OnPostThinkPost);
}

public void OnPreThink(int client)
{
	if (g_CVar_sv_bombanywhere.IntValue >= 1)
	{
		if(IsClientInGame(client) && IsPlayerAlive(client))
		{
			SetEntProp(client, Prop_Send, "m_bInBombZone", 1);
		}
	}
}

public void OnPostThinkPost(int client)
{
	if(IsClientInGame(client) && IsPlayerAlive(client))
	{
		if(g_bInBuyZoneAll || g_bInBuyZone[client])
			SetEntProp(client, Prop_Send, "m_bInBuyZone", 1);
	}
}

public void Event_WeaponFire(Handle hEvent, char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	if(!g_bInfAmmoAll && !g_bInfAmmo[client])
		return;

	int weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon", 0);
	if(IsValidEntity(weapon))
	{
		if(weapon == GetPlayerWeaponSlot(client, 0) || weapon == GetPlayerWeaponSlot(client, 1))
		{
			if(GetEntProp(weapon, Prop_Send, "m_iState", 4, 0) == 2 && GetEntProp(weapon, Prop_Send, "m_iClip1", 4, 0))
			{
				int toAdd = 1;
				char weaponClassname[128];
				GetEntityClassname(weapon, weaponClassname, sizeof(weaponClassname));

				if(StrEqual(weaponClassname, "weapon_glock", true) || StrEqual(weaponClassname, "weapon_famas", true))
				{
					if(GetEntProp(weapon, Prop_Send, "m_bBurstMode"))
					{
						switch (GetEntProp(weapon, Prop_Send, "m_iClip1"))
						{
							case 1:
							{
								toAdd = 1;
							}
							case 2:
							{
								toAdd = 2;
							}
							default:
							{
								toAdd = 3;
							}
						}
					}
				}

				SetEntProp(weapon, Prop_Send, "m_iClip1", GetEntProp(weapon, Prop_Send, "m_iClip1", 4, 0) + toAdd, 4, 0);
			}
		}
	}

	return;
}

public Action Command_Health(int client, int argc)
{
	if(argc < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_hp <#userid|name> <value>");
		return Plugin_Handled;
	}

	char sArgs[65];
	char sArgs2[20];
	char sTargetName[MAX_TARGET_LENGTH];
	int iTargets[MAXPLAYERS];
	int iTargetCount;
	bool bIsML;

	GetCmdArg(1, sArgs, sizeof(sArgs));
	GetCmdArg(2, sArgs2, sizeof(sArgs2));

	int amount = clamp(StringToInt(sArgs2), 1, 0x7FFFFFFF);

	if((iTargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS, COMMAND_FILTER_ALIVE, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}

	for(int i = 0; i < iTargetCount; i++)
	{
		SetEntProp(iTargets[i], Prop_Send, "m_iHealth", amount, 1);
	}

	if(bIsML)
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Set health to \x04%d\x01 on target \x04%s", amount, sTargetName);
		LogAction(client, -1, "\"%L\" set health to \"%d\" on target \"%s\"", client, amount, sTargetName);
	}
	else
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Set health to \x04%d\x01 on target \x04%s", amount, sTargetName);
		LogAction(client, iTargets[0], "\"%L\" set health to \"%d\" on target \"%L\"", client, amount, iTargets[0]);
	}

	return Plugin_Handled;
}

public Action Command_Armor(int client, int argc)
{
	if(argc < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_armor <#userid|name> <value>");
		return Plugin_Handled;
	}

	char sArgs[65];
	char sArgs2[20];
	char sTargetName[MAX_TARGET_LENGTH];
	int iTargets[MAXPLAYERS];
	int iTargetCount;
	bool bIsML;

	GetCmdArg(1, sArgs, sizeof(sArgs));
	GetCmdArg(2, sArgs2, sizeof(sArgs2));

	int amount = clamp(StringToInt(sArgs2), 0, 0xFF);

	if((iTargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS, COMMAND_FILTER_ALIVE, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}

	for(int i = 0; i < iTargetCount; i++)
	{
		SetEntProp(iTargets[i], Prop_Send, "m_ArmorValue", amount, 1);
	}

	if(bIsML)
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Set kevlar to \x04%d\x01 on target \x04%s", amount, sTargetName);
		LogAction(client, -1, "\"%L\" set kevlar to \"%d\" on target \"%s\"", client, amount, sTargetName);
	}
	else
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Set kevlar to \x04%d\x01 on target \x04%s", amount, sTargetName);
		LogAction(client, iTargets[0], "\"%L\" set kevlar to \"%d\" on target \"%L\"", client, amount, iTargets[0]);
	}

	return Plugin_Handled;
}

public Action Command_Weapon(int client, int argc)
{
	if(argc < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_weapon <#userid|name> <weapon> [clip] [ammo]");
		return Plugin_Handled;
	}

	int ammo = 2500;
	int clip = -1;

	char sArgs[65];
	GetCmdArg(1, sArgs, sizeof(sArgs));

	char sArgs2[65];
	GetCmdArg(2, sArgs2, sizeof(sArgs2));

	char sWeapon[65];

	if(strncmp(sArgs2, "weapon_", 7) != 0 && strncmp(sArgs2, "item_", 5) != 0 && !StrEqual(sArgs2, "nvg", false))
		Format(sWeapon, sizeof(sWeapon), "weapon_%s", sArgs2);
	else
		strcopy(sWeapon, sizeof(sWeapon), sArgs2);

	if(StrContains(sWeapon, "grenade", false) != -1 || StrContains(sWeapon, "flashbang", false) != -1 || strncmp(sArgs2, "item_", 5) == 0)
		ammo = -1;

	if(client >= 1)
	{
		AdminId id = GetUserAdmin(client);
		int superadmin = GetAdminFlag(id, Admin_Custom3);

		if(!superadmin)
		{
			if(StrEqual(sWeapon, "weapon_c4", false) || StrEqual(sWeapon, "weapon_smokegrenade", false) || StrEqual(sWeapon, "item_defuser", false))
			{
				ReplyToCommand(client, "[SM] This weapon is restricted!");
				return Plugin_Handled;
			}
		}
	}

	if(argc >= 3)
	{
		char sArgs3[20];
		GetCmdArg(3, sArgs3, sizeof(sArgs3));

		if(StringToIntEx(sArgs3, clip) == 0)
		{
			ReplyToCommand(client, "[SM] Invalid Clip Value");
			return Plugin_Handled;
		}
	}

	if(argc >= 4)
	{
		char sArgs4[20];
		GetCmdArg(4, sArgs4, sizeof(sArgs4));

		if(StringToIntEx(sArgs4, ammo) == 0)
		{
			ReplyToCommand(client, "[SM] Invalid Ammo Value");
			return Plugin_Handled;
		}
	}

	if(StrContains(sWeapon, "grenade", false) != -1 || StrContains(sWeapon, "flashbang", false) != -1)
	{
		int tmp = ammo;
		ammo = clip;
		clip = tmp;
	}

	char sTargetName[MAX_TARGET_LENGTH];
	int iTargets[MAXPLAYERS];
	int iTargetCount;
	bool bIsML;

	if((iTargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS, COMMAND_FILTER_ALIVE, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}

	if(StrEqual(sWeapon, "nvg", false))
	{
		for(int i = 0; i < iTargetCount; i++)
			SetEntProp(iTargets[i], Prop_Send, "m_bHasNightVision", 1, 1);
	}
	else if(StrEqual(sWeapon, "item_defuser", false))
	{
		for(int i = 0; i < iTargetCount; i++)
			SetEntProp(iTargets[i], Prop_Send, "m_bHasDefuser", 1);
	}
	else
	{
		for(int i = 0; i < iTargetCount; i++)
		{
			int ent = GivePlayerItem(iTargets[i], sWeapon);

			if(ent == -1) {
				ReplyToCommand(client, "[SM] Invalid Weapon");
				return Plugin_Handled;
			}

			if(clip != -1)
				SetEntProp(ent, Prop_Send, "m_iClip1", clip);

			if(ammo != -1)
			{
				int PrimaryAmmoType = GetEntProp(ent, Prop_Data, "m_iPrimaryAmmoType");

				if(PrimaryAmmoType != -1)
					SetEntProp(iTargets[i], Prop_Send, "m_iAmmo", ammo, _, PrimaryAmmoType);
			}

			if(strncmp(sArgs2, "item_", 5) != 0 && !StrEqual(sWeapon, "weapon_hegrenade", false))
				EquipPlayerWeapon(iTargets[i], ent);

			if(ammo != -1)
			{
				int PrimaryAmmoType = GetEntProp(ent, Prop_Data, "m_iPrimaryAmmoType");

				if(PrimaryAmmoType != -1)
					SetEntProp(iTargets[i], Prop_Send, "m_iAmmo", ammo, _, PrimaryAmmoType);
			}
		}
	}

	if(bIsML)
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Gave \x04%s\x01 to target \x04%s", sWeapon, sTargetName);
		LogAction(client, -1, "\"%L\" gave \"%s\" to target \"%s\"", client, sWeapon, sTargetName);
	}
	else
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Gave \x04%s\x01 to target \x04%s", sWeapon, sTargetName);
		LogAction(client, iTargets[0], "\"%L\" gave \"%s\" to target \"%L\"", client, sWeapon, iTargets[0]);
	}

	return Plugin_Handled;
}

public Action Command_Strip(int client, int argc)
{
	if(argc < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_strip <#userid|name>");
		return Plugin_Handled;
	}

	char sArgs[65];
	GetCmdArg(1, sArgs, sizeof(sArgs));

	char sTargetName[MAX_TARGET_LENGTH];
	int iTargets[MAXPLAYERS];
	int iTargetCount;
	bool bIsML;

	if((iTargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS, COMMAND_FILTER_ALIVE, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}

	for(int i = 0; i < iTargetCount; i++)
	{
		for(int j = 0; j < 5; j++)
		{
			int w = -1;

			while ((w = GetPlayerWeaponSlot(iTargets[i], j)) != -1)
			{
				if(IsValidEntity(w) && IsValidEdict(w))
				{
					RemovePlayerItem(iTargets[i], w);
					AcceptEntityInput(w, "Kill");
				}
			}
		}
	}

	if(bIsML)
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Stripped all weapons from target \x04%s", sTargetName);
		LogAction(client, -1, "\"%L\" stripped all weapons from target \"%s\"", client, sTargetName);
	}
	else
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Stripped all weapons from target \x04%s", sTargetName);
		LogAction(client, iTargets[0], "\"%L\" stripped all weapons from target \"%L\"", client, iTargets[0]);
	}
	
	return Plugin_Handled;
}

public Action Command_BuyZone(int client, int argc)
{
	if(argc < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_buyzone <#userid|name> <0|1>");
		return Plugin_Handled;
	}

	char sArgs[65];
	GetCmdArg(1, sArgs, sizeof(sArgs));

	int value = -1;
	char sArgs2[20];
	GetCmdArg(2, sArgs2, sizeof(sArgs2));

	if(StringToIntEx(sArgs2, value) == 0)
	{
		ReplyToCommand(client, "[SM] Invalid Value");
		return Plugin_Handled;
	}

	char sTargetName[MAX_TARGET_LENGTH];

	if(StrEqual(sArgs, "@all", false))
	{
		sTargetName = "all players";
		g_bInBuyZoneAll = value ? true : false;
	}
	else
	{
		int iTargets[MAXPLAYERS];
		int iTargetCount;
		bool bIsML;

		if((iTargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS, COMMAND_FILTER_ALIVE, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
		{
			ReplyToTargetError(client, iTargetCount);
			return Plugin_Handled;
		}

		for(int i = 0; i < iTargetCount; i++)
		{
			g_bInBuyZone[iTargets[i]] = value ? true : false;
		}
	}

	ShowActivity2(client, "\x01[SM] \x04", "%s\x01 permanent buyzone on target \x04%s", (value ? "Enabled" : "Disabled"), sTargetName);
	LogAction(client, -1, "\"%L\" %s permanent buyzone on target \"%s\"", client, (value ? "enabled" : "disabled"), sTargetName);

	return Plugin_Handled;
}

public Action Command_InfAmmo(int client, int argc)
{
	if(argc < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_iammo <#userid|name> <0|1>");
		return Plugin_Handled;
	}

	char sArgs[65];
	GetCmdArg(1, sArgs, sizeof(sArgs));

	int value = -1;
	char sArgs2[20];
	GetCmdArg(2, sArgs2, sizeof(sArgs2));

	if(StringToIntEx(sArgs2, value) == 0)
	{
		ReplyToCommand(client, "[SM] Invalid Value");
		return Plugin_Handled;
	}

	char sTargetName[MAX_TARGET_LENGTH];

	if(StrEqual(sArgs, "@all", false))
	{
		sTargetName = "all players";
		g_bInfAmmoAll = value ? true : false;

		if(!g_bInfAmmoAll)
		{
			for(int i = 0; i < MAXPLAYERS; i++)
				g_bInfAmmo[i] = false;
		}
	}
	else
	{
		int iTargets[MAXPLAYERS];
		int iTargetCount;
		bool bIsML;

		if((iTargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS, COMMAND_FILTER_ALIVE, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
		{
			ReplyToTargetError(client, iTargetCount);
			return Plugin_Handled;
		}

		for(int i = 0; i < iTargetCount; i++)
		{
			g_bInfAmmo[iTargets[i]] = value ? true : false;
		}
	}

	ShowActivity2(client, "\x01[SM] \x04", "%s\x01 infinite ammo on target \x04%s", (value ? "Enabled" : "Disabled"), sTargetName);
	LogAction(client, -1, "\"%L\" %s infinite ammo on target \"%s\"", client, (value ? "enabled" : "disabled"), sTargetName);

	if(g_bInfAmmoAll)
	{
		if(!g_bInfAmmoHooked)
		{
			HookEvent("weapon_fire", Event_WeaponFire);
			g_bInfAmmoHooked = true;
		}

		return Plugin_Handled;
	}

	for(int i = 0; i < MAXPLAYERS; i++)
	{
		if(g_bInfAmmo[i])
		{
			if(!g_bInfAmmoHooked)
			{
				HookEvent("weapon_fire", Event_WeaponFire);
				g_bInfAmmoHooked = true;
			}

			return Plugin_Handled;
		}
	}

	if(g_bInfAmmoHooked)
	{
		UnhookEvent("weapon_fire", Event_WeaponFire);
		g_bInfAmmoHooked = false;
	}

	return Plugin_Handled;
}

public Action Command_Speed(int client, int argc)
{
	if(argc < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_speed <#userid|name> <value>");
		return Plugin_Handled;
	}

	char sArgs[65];
	char sArgs2[20];
	char sTargetName[MAX_TARGET_LENGTH];
	int iTargets[MAXPLAYERS];
	int iTargetCount;
	bool bIsML;

	GetCmdArg(1, sArgs, sizeof(sArgs));
	GetCmdArg(2, sArgs2, sizeof(sArgs2));

	float speed = clamp(StringToFloat(sArgs2), 0.0, 100.0);

	if((iTargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS, COMMAND_FILTER_ALIVE, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}

	for(int i = 0; i < iTargetCount; i++)
	{
		SetEntPropFloat(iTargets[i], Prop_Data, "m_flLaggedMovementValue", speed);
	}

	if(bIsML)
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Set speed to \x04%.2f\x01 on target \x04%s", speed, sTargetName);
		LogAction(client, -1, "\"%L\" set speed to \"%.2f\" on target \"%s\"", client, speed, sTargetName);
	}
	else
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Set speed to \x04%.2f\x01 on target \x04%s", speed, sTargetName);
		LogAction(client, iTargets[0], "\"%L\" set speed to \"%.2f\" on target \"%L\"", client, speed, iTargets[0]);
	}

	return Plugin_Handled;
}

public Action Command_Respawn(int client, int argc)
{
	if(argc < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_respawn <#userid|name>");
		return Plugin_Handled;
	}

	char sArgs[64];
	char sTargetName[MAX_TARGET_LENGTH];
	int iTargets[MAXPLAYERS];
	int iTargetCount;
	bool bIsML;
	bool bDidRespawn;

	GetCmdArg(1, sArgs, sizeof(sArgs));

	if((iTargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS, COMMAND_FILTER_DEAD, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}

	for(int i = 0; i < iTargetCount; i++)
	{
		if(GetClientTeam(iTargets[i]) == CS_TEAM_SPECTATOR || GetClientTeam(iTargets[i]) == CS_TEAM_NONE)
			continue;

		bDidRespawn = true;
		CS_RespawnPlayer(iTargets[i]);
	}

	if(bDidRespawn)
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Respawned \x04%s", sTargetName);
		LogAction(client, -1, "\"%L\" respawned \"%s\"", client, sTargetName);
	}

	return Plugin_Handled;
}

public Action Command_Cash(int client, int argc)
{
	if(argc < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_cash <#userid|name> <value>");
		return Plugin_Handled;
	}

	char sArgs[64];
	char sArgs2[32];
	char sTargetName[MAX_TARGET_LENGTH];
	int iTargets[MAXPLAYERS];
	int iTargetCount;
	bool bIsML;

	GetCmdArg(1, sArgs, sizeof(sArgs));
	GetCmdArg(2, sArgs2, sizeof(sArgs2));

	int iCash = clamp(StringToInt(sArgs2), 0, 0xFFFF);

	if((iTargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS, COMMAND_FILTER_ALIVE, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}

	for(int i = 0; i < iTargetCount; i++)
	{
		SetEntProp(iTargets[i], Prop_Send, "m_iAccount", iCash);
	}

	if(bIsML)
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Set cash to \x04%d\x01 on target \x04%s", iCash, sTargetName);
		LogAction(client, -1, "\"%L\" set cash to \"%d\" on target \"%s\"", client, iCash, sTargetName);
	}
	else
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Set cash to \x04%d\x01 on target \x04%s", iCash, sTargetName);
		LogAction(client, iTargets[0], "\"%L\" set cash to \"%d\" on target \"%L\"", client, iCash, iTargets[0]);
	}

	return Plugin_Handled;
}

public Action Command_ModelScale(int client, int argc)
{
	if(argc < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_resize/sm_modelscale <#userid|name> <scale>");
		return Plugin_Handled;
	}

	char sArgs[64];
	char sArgs2[32];
	char sTargetName[MAX_TARGET_LENGTH];
	int iTargets[MAXPLAYERS];
	int iTargetCount;
	bool bIsML;

	GetCmdArg(1, sArgs, sizeof(sArgs));
	GetCmdArg(2, sArgs2, sizeof(sArgs2));

	float fScale = clamp(StringToFloat(sArgs2), 0.0, 100.0);

	if((iTargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS, COMMAND_FILTER_ALIVE, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}

	for(int i = 0; i < iTargetCount; i++)
	{
		SetEntPropFloat(iTargets[i], Prop_Send, "m_flModelScale", fScale);
	}

	if(bIsML)
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Set model scale to \x04%.2f\x01 on target \x04%s", fScale, sTargetName);
		LogAction(client, -1, "\"%L\" set model scale to \"%.2f\" on target \"%s\"", client, fScale, sTargetName);
	}
	else
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Set model scale to \x04%.2f\x01 on target \x04%s", fScale, sTargetName);
		LogAction(client, iTargets[0], "\"%L\" set model scale to \"%.2f\" on target \"%L\"", client, fScale, iTargets[0]);
	}

	return Plugin_Handled;
}

public Action Command_SetModel(int client, int argc)
{
	if(argc < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_setmodel <#userid|name> <modelpath>");
		return Plugin_Handled;
	}

	char sArgs[32];
	char sArgs2[PLATFORM_MAX_PATH];
	char sTargetName[MAX_TARGET_LENGTH];
	int iTargets[MAXPLAYERS];
	int iTargetCount;
	bool bIsML;

	GetCmdArg(1, sArgs, sizeof(sArgs));
	GetCmdArg(2, sArgs2, sizeof(sArgs2));

	if((iTargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS, COMMAND_FILTER_ALIVE, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}

	if(!FileExists(sArgs2, true))
	{
		ReplyToCommand(client, "[SM] File \"%s\" does not exist.", sArgs2);
		return Plugin_Handled;
	}

	if(!IsModelPrecached(sArgs2))
	{
		ReplyToCommand(client, "[SM] File \"%s\" is not precached, attempting to precache now.", sArgs2);

		PrecacheModel(sArgs2);
	}

	for(int i = 0; i < iTargetCount; i++)
	{
		SetEntityModel(iTargets[i], sArgs2);
	}

	if(bIsML)
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Set model to \x04%s\x01 on target \x04%s", sArgs2, sTargetName);
		LogAction(client, -1, "\"%L\" set model to \"%s\" on target \"%s\"", client, sArgs2, sTargetName);
	}
	else
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Set model to \x04%s\x01 on target \x04%s", sArgs2, sTargetName);
		LogAction(client, iTargets[0], "\"%L\" set model to \"%s\" on target \"%L\"", client, sArgs2, iTargets[0]);
	}

	return Plugin_Handled;
}

public Action Command_SetScore(int client, int argc)
{
	if(argc < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_setscore <#userid|name> <value>");
		return Plugin_Handled;
	}

	char sArgs[32];
	char sArgs2[32];
	char sTargetName[MAX_TARGET_LENGTH];
	int iTargets[MAXPLAYERS];
	int iTargetCount;
	bool bIsML;

	GetCmdArg(1, sArgs, sizeof(sArgs));
	GetCmdArg(2, sArgs2, sizeof(sArgs2));

	int iVal = StringToInt(sArgs2);

	if((iTargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS, 0, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}

	for(int i = 0; i < iTargetCount; i++)
	{
		SetEntProp(iTargets[i], Prop_Data, "m_iFrags", iVal);
	}

	if(bIsML)
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Set score to \x04%d\x01 on target \x04%s", iVal, sTargetName);
		LogAction(client, -1, "\"%L\" set score to \"%d\" on target \"%s\"", client, iVal, sTargetName);
	}
	else
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Set score to \x04%d\x01 on target \x04%s", iVal, sTargetName);
		LogAction(client, iTargets[0], "\"%L\" set score to \"%d\" on target \"%L\"", client, iVal, iTargets[0]);
	}

	return Plugin_Handled;
}

public Action Command_SetDeath(int client, int argc)
{
	if(argc < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_setdeath <#userid|name> <value>");
		return Plugin_Handled;
	}

	char sArgs[32];
	char sArgs2[32];
	char sTargetName[MAX_TARGET_LENGTH];
	int iTargets[MAXPLAYERS];
	int iTargetCount;
	bool bIsML;

	GetCmdArg(1, sArgs, sizeof(sArgs));
	GetCmdArg(2, sArgs2, sizeof(sArgs2));

	int iVal = StringToInt(sArgs2);

	if((iTargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS, 0, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}

	for(int i = 0; i < iTargetCount; i++)
	{
		SetEntProp(iTargets[i], Prop_Data, "m_iDeaths", iVal);
	}

	if(bIsML)
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Set death to \x04%d\x01 on target \x04%s", iVal, sTargetName);
		LogAction(client, -1, "\"%L\" set death to \"%d\" on target \"%s\"", client, iVal, sTargetName);
	}
	else
	{
		ShowActivity2(client, "\x01[SM] \x04", "\x01Set death to \x04%d\x01 on target \x04%s", iVal, sTargetName);
		LogAction(client, iTargets[0], "\"%L\" set death to \"%d\" on target \"%L\"", client, iVal, iTargets[0]);
	}

	return Plugin_Handled;
}

public Action Command_SetTeamScore(int client, int argc)
{
	if(argc < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_setteamscore <team> <value>");
		return Plugin_Handled;
	}

	char sArgs[32];
	char sArgs2[32];

	GetCmdArg(1, sArgs, sizeof(sArgs));
	GetCmdArg(2, sArgs2, sizeof(sArgs2));

	int iVal = StringToInt(sArgs2);

	if(strcmp(sArgs, "@ct", false) == 0 || strcmp(sArgs, "@cts", false) == 0)
	{
		SetTeamScore(CS_TEAM_CT, iVal);
		CS_SetTeamScore(CS_TEAM_CT, iVal);

		ShowActivity2(client, "\x01[SM] \x04", "\x01Set team-score to \x04%d\x01 on team \x04Counter-Terrorists", iVal);
		LogAction(client, -1, "\"%L\" set team-score to \"%d\" on team \"Counter-Terrorists\"", client, iVal);
	}
	else if(strcmp(sArgs, "@t", false) == 0 || strcmp(sArgs, "@ts", false) == 0)
	{
		SetTeamScore(CS_TEAM_T, iVal);
		CS_SetTeamScore(CS_TEAM_T, iVal);

		ShowActivity2(client, "\x01[SM] \x04", "\x01Set team-score to \x04%d\x01 on team \x04Terrorists", iVal);
		LogAction(client, -1, "\"%L\" set team-score to \"%d\" on team \"Terrorists\"", client, iVal);
	}
	else
	{
		ReplyToCommand(client, "[SM] Invalid team.");
	}

	return Plugin_Handled;
}

public Action Command_WAILA(int client, int argc)
{
	if(!client)
	{
		PrintToServer("[SM] Cannot use command from server console.");
		return Plugin_Handled;
	}

	float vecEyeAngles[3];
	float vecEyeOrigin[3];

	GetClientEyeAngles(client, vecEyeAngles);
	GetClientEyePosition(client, vecEyeOrigin);

	Handle hTraceRay = TR_TraceRayFilterEx(vecEyeOrigin, vecEyeAngles, MASK_ALL, RayType_Infinite, TraceEntityFilter_FilterCaller, client);

	if(TR_DidHit(hTraceRay))
	{
		float vecEndPos[3];
		char sModelPath[PLATFORM_MAX_PATH];
		char sClsName[64];
		char sNetClsName[64];
		char sTargetname[64];
		int iEntity;
		int iEntityModelIdx;

		TR_GetEndPosition(vecEndPos, hTraceRay);

		if((iEntity = TR_GetEntityIndex(hTraceRay)) <= 0)
		{
			PrintToChat(client, "[SM] Trace hit the world.");

			delete hTraceRay;

			return Plugin_Handled;
		}

		GetEntPropString(iEntity, Prop_Data, "m_ModelName", sModelPath, sizeof(sModelPath));
		GetEntityClassname(iEntity, sClsName, sizeof(sClsName));
		GetEntityNetClass(iEntity, sNetClsName, sizeof(sNetClsName));
		GetEntPropString(iEntity, Prop_Data, "m_iName", sTargetname, sizeof(sTargetname));
		iEntityModelIdx = GetEntProp(iEntity, Prop_Send, "m_nModelIndex");

		PrintToConsole(client, "Entity Index: %i\nTarget name: %s\nModel Path: %s\nModel Index: %i\nClass Name: %s\nNet Class Name: %s", iEntity, sTargetname, sModelPath, iEntityModelIdx, sClsName, sNetClsName);

		PrintToChat(client, "[SM] Trace hit something, check your console for more information.");

		delete hTraceRay;

		return Plugin_Handled;
	}

	delete hTraceRay;

	PrintToChat(client, "[SM] Couldn't find anything under your crosshair.");

	return Plugin_Handled;
}

stock bool TraceEntityFilter_FilterCaller(int entity, int contentsMask, int client)
{
	return entity != client;
}

public Action Command_ForceCVar(int client, int argc)
{
	if(argc < 3)
	{
		ReplyToCommand(client, "[SM] Usage: sm_fcvar <#userid|name> <cvar> <value>");
		return Plugin_Handled;
	}

	char sArg[65];
	char sArg2[65];
	char sArg3[65];
	char sTargetName[MAX_TARGET_LENGTH];
	int iTargets[MAXPLAYERS];
	int iTargetCount;
	bool bIsML;

	GetCmdArg(1, sArg, sizeof(sArg));
	GetCmdArg(2, sArg2, sizeof(sArg2));
	GetCmdArg(3, sArg3, sizeof(sArg3));

	ConVar cvar = FindConVar(sArg2);

	if(cvar == null)
	{
		ReplyToCommand(client, "[SM] No such cvar.");
		return Plugin_Handled;
	}

	if((iTargetCount = ProcessTargetString(sArg, client, iTargets, MAXPLAYERS, COMMAND_FILTER_NO_BOTS, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}

	for(int i = 0; i < iTargetCount; i++)
	{
		cvar.ReplicateToClient(iTargets[i], sArg3);
	}

	return Plugin_Handled;
}

public Action Command_SetClanTag(int client, int argc)
{
	if(argc < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_setclantag <#userid|name> [text]");
		return Plugin_Handled;
	}

	char sArg[64];
	char sArg2[64];
	char sTargetName[MAX_TARGET_LENGTH];
	int iTargets[MAXPLAYERS];
	int iTargetCount;
	bool bIsML;

	GetCmdArg(1, sArg, sizeof(sArg));
	GetCmdArg(2, sArg2, sizeof(sArg2));

	if((iTargetCount = ProcessTargetString(sArg, client, iTargets, MAXPLAYERS, 0, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}

	for(int i = 0; i < iTargetCount; i++)
	{
		CS_SetClientClanTag(iTargets[i], sArg2);
	}

	return Plugin_Handled;
}

public Action Command_FakeCommand(int client, int argc)
{
	if (argc < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_fakecommand <#userid|name> [command] [args]");
		return Plugin_Handled;
	}

	char sArg[64];
	char sArg2[64];
	char sArg3[64];
	char sTargetName[MAX_TARGET_LENGTH];
	int iTargets[MAXPLAYERS];
	int iTargetCount;
	bool bIsML;

	GetCmdArg(1, sArg, sizeof(sArg));
	GetCmdArg(2, sArg2, sizeof(sArg2));
	GetCmdArg(3, sArg3, sizeof(sArg3));

	if((iTargetCount = ProcessTargetString(sArg, client, iTargets, MAXPLAYERS, COMMAND_FILTER_CONNECTED, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}

	bool bCanServerExecute = false;

	for(int i = 0; i < sizeof(g_sServerCanExecuteCmds); i++)
	{
		if(strcmp(g_sServerCanExecuteCmds[i], sArg2) == 0)
		{
			bCanServerExecute = true;
			break;
		}
	}

	for(int i = 0; i < iTargetCount; i++)
	{
		if(bCanServerExecute)
			ClientCommand(iTargets[i], "%s %s", sArg2, sArg3);
		else
			FakeClientCommand(iTargets[i], "%s %s", sArg2, sArg3);
	}

	return Plugin_Handled;
}

stock any clamp(any input, any min, any max)
{
	any retval = input < min ? min : input;

	return retval > max ? max : retval;
}
