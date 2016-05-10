#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <cstrike>

#undef REQUIRE_PLUGIN
#include <adminmenu>
#define REQUIRE_PLUGIN

#pragma newdecls required

enum
{
	AABBMinX = 0,
	AABBMaxX = 1,
	AABBMinY = 2,
	AABBMaxY = 3,
	AABBMinZ = 4,
	AABBMaxZ = 5,
	AABBTotalPoints = 6
}

Handle g_hDatabase = null;
Handle g_hTraceTimer = null;
Handle g_hTopMenu = null;
ConVar g_cvarHookedDecalFrequency = null;
ConVar g_cvarDecalFrequency = null;
ConVar g_cvarUseProximityCheck = null;

bool g_bLoadedLate;
bool g_bAllowSpray;
bool g_bSQLite;
bool g_bGotBans;
bool g_bGotBlacklist;
bool g_bFullyConnected;

char g_sBanIssuer[MAXPLAYERS + 1][64];
char g_sBanIssuerSID[MAXPLAYERS + 1][32];
char g_sBanReason[MAXPLAYERS + 1][32];
char g_sSprayHash[MAXPLAYERS + 1][16];

bool g_bSprayBanned[MAXPLAYERS + 1];
bool g_bSprayHashBanned[MAXPLAYERS + 1];
bool g_bInvokedThroughTopMenu[MAXPLAYERS + 1];
bool g_bInvokedThroughListMenu[MAXPLAYERS + 1];

int g_iSprayLifetime[MAXPLAYERS + 1];
int g_iSprayBanTimestamp[MAXPLAYERS + 1];
int g_iSprayUnbanTimestamp[MAXPLAYERS + 1] = { -1, ... };
int g_iSprayBanTarget[MAXPLAYERS + 1];
int g_iSprayUnbanTarget[MAXPLAYERS + 1];
int g_iSprayTraceTarget[MAXPLAYERS + 1];
int g_iBanTarget[MAXPLAYERS + 1];

float ACTUAL_NULL_VECTOR[3];
float g_fNextSprayTime[MAXPLAYERS + 1];
float g_vecSprayOrigin[MAXPLAYERS + 1][3];
float g_SprayAABB[MAXPLAYERS + 1][AABBTotalPoints];

public Plugin myinfo =
{
	name		= "Spray Manager",
	description	= "A plugin to help manage player sprays.",
	author		= "Obus",
	version		= "1.2.0",
	url			= "https://github.com/CSSZombieEscape/sm-plugins/tree/master/SprayManager"
}

public APLRes AskPluginLoad2(Handle hThis, bool bLate, char[] err, int iErrLen)
{
	g_bLoadedLate = bLate;

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");

	RegAdminCmd("sm_spray", Command_AdminSpray, ADMFLAG_GENERIC, "Spray a clients spray");
	RegAdminCmd("sm_sprayban", Command_SprayBan, ADMFLAG_GENERIC, "Ban a client from spraying");
	RegAdminCmd("sm_sprayunban", Command_SprayUnban, ADMFLAG_GENERIC, "Unban a client and allow them to spray");
	RegAdminCmd("sm_banspray", Command_BanSpray, ADMFLAG_GENERIC, "Ban a clients spray from being sprayed (Note: This will not spray-ban the client, it will only ban the spray which they are currently using)");
	RegAdminCmd("sm_unbanspray", Command_UnbanSpray, ADMFLAG_GENERIC, "Unban a clients spray (Note: This will not spray-unban the client, it will only unban the spray which they are currently using)");
	RegAdminCmd("sm_tracespray", Command_TraceSpray, ADMFLAG_GENERIC, "Finds a spray under your crosshair");
	RegAdminCmd("sm_spraytrace", Command_TraceSpray, ADMFLAG_GENERIC, "Finds a spray under your crosshair");
	RegAdminCmd("sm_removespray", Command_RemoveSpray, ADMFLAG_GENERIC, "Finds and removes a spray under your crosshair");
	RegAdminCmd("sm_spraymanagerupdatedb", Command_SprayManager_UpdateInfo, ADMFLAG_CHEATS, "Updates all clients info");
	RegAdminCmd("sm_spraymanagerrefreshdb", Command_SprayManager_UpdateInfo, ADMFLAG_CHEATS, "Updates all clients info");
	RegAdminCmd("sm_spraymanagerreloaddb", Command_SprayManager_UpdateInfo, ADMFLAG_CHEATS, "Updates all clients info");

	AddTempEntHook("Player Decal", HookDecal);
	AddNormalSoundHook(HookSprayer);

	TopMenu hTopMenu;

	if (LibraryExists("adminmenu") && ((hTopMenu = GetAdminTopMenu()) != INVALID_HANDLE))
		OnAdminMenuReady(hTopMenu);

	if (g_cvarHookedDecalFrequency != null)
		delete g_cvarHookedDecalFrequency;

	if (g_cvarDecalFrequency != null)
		delete g_cvarDecalFrequency;

	if (g_cvarUseProximityCheck != null)
		delete g_cvarUseProximityCheck;

	g_cvarHookedDecalFrequency = FindConVar("decalfrequency");
	g_cvarHookedDecalFrequency.IntValue = 0;

	g_cvarDecalFrequency = CreateConVar("sm_decalfrequency", "10", "Controls how often clients can spray", FCVAR_NOTIFY);

	HookConVarChange(g_cvarHookedDecalFrequency, CVarHook_DecalFrequency);

	g_cvarUseProximityCheck = CreateConVar("sm_spraymanager_blockoverspraying", "1", "Allows or disallows people to overspray other people.", FCVAR_NOTIFY);

	AutoExecConfig(true, "plugin.spraymanager");

	if (g_hDatabase != null)
		delete g_hDatabase;

	g_hTraceTimer = CreateTimer(0.25, PerformPlayerTraces, _, TIMER_REPEAT);

	InitializeSQL();
}

public void OnPluginEnd()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i) || IsFakeClient(i))
			continue;

		if (g_vecSprayOrigin[i][0] == 0.0)
			continue;

		g_bAllowSpray = true;
		SprayClientDecal(i, 0, ACTUAL_NULL_VECTOR);
	}

	RemoveTempEntHook("Player Decal", HookDecal);
	RemoveNormalSoundHook(HookSprayer);

	if (g_hDatabase != null)
	{
		SQL_UnlockDatabase(g_hDatabase);
		delete g_hDatabase;
	}

	if (g_hTraceTimer != null)
		KillTimer(g_hTraceTimer);
}

public void OnClientPostAdminCheck(int client)
{
	if (g_hDatabase != null)
	{
		ClearPlayerInfo(client);
		UpdatePlayerInfo(client);
		UpdateSprayHashInfo(client);
	}
}

public void OnClientDisconnect(int client)
{
	g_bAllowSpray = true;
	SprayClientDecal(client, 0, ACTUAL_NULL_VECTOR);
	ClearPlayerInfo(client);
}

public Action CS_OnTerminateRound(float &fDelay, CSRoundEndReason &reason)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i))
			continue;

		if (!IsVectorZero(g_vecSprayOrigin[i]))
			g_iSprayLifetime[i]++;

		if (g_iSprayLifetime[i] >= 2)
		{
			g_bAllowSpray = true;
			SprayClientDecal(i, 0, ACTUAL_NULL_VECTOR);
			g_iSprayLifetime[i] = 0;
		}
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse)
{
	if (!impulse || impulse != 201)
		return Plugin_Continue;

	if (CheckCommandAccess(client, "sm_sprayban", ADMFLAG_GENERIC))
	{
		if (!g_bSprayBanned[client] && !g_bSprayHashBanned[client])
		{
			if (TracePlayerAnglesRanged(client, 128.0))
				return Plugin_Continue;

			ForceSpray(client, client, false);
			g_fNextSprayTime[client] = 0.0;
		}
	}

	return Plugin_Continue;
}

public void OnAdminMenuReady(Handle hAdminMenu)
{
	if (hAdminMenu == g_hTopMenu)
		return;

	g_hTopMenu = CloneHandle(hAdminMenu);

	TopMenuObject hMenuObj = AddToTopMenu(g_hTopMenu, "SprayManagerCommands", TopMenuObject_Category, TopMenu_Main_Handler, INVALID_TOPMENUOBJECT);

	if (hMenuObj == INVALID_TOPMENUOBJECT)
		return;

	AddToTopMenu(g_hTopMenu, "SprayManager_Spraybanlist", TopMenuObject_Item, Handler_SprayBanList, hMenuObj);
	AddToTopMenu(g_hTopMenu, "SprayManager_Tracespray", TopMenuObject_Item, Handler_TraceSpray, hMenuObj, "sm_tracespray", ADMFLAG_GENERIC);
	AddToTopMenu(g_hTopMenu, "SprayManager_Spray", TopMenuObject_Item, Handler_Spray, hMenuObj, "sm_spray", ADMFLAG_GENERIC);
	AddToTopMenu(g_hTopMenu, "SprayManager_Sprayban", TopMenuObject_Item, Handler_SprayBan, hMenuObj, "sm_sprayban", ADMFLAG_GENERIC);
	AddToTopMenu(g_hTopMenu, "SprayManager_Sprayunban", TopMenuObject_Item, Handler_SprayUnban, hMenuObj, "sm_sprayunban", ADMFLAG_GENERIC);
	AddToTopMenu(g_hTopMenu, "SprayManager_Banspray", TopMenuObject_Item, Handler_BanSpray, hMenuObj, "sm_banspray", ADMFLAG_GENERIC);
	AddToTopMenu(g_hTopMenu, "SprayManager_Unbanspray", TopMenuObject_Item, Handler_UnbanSpray, hMenuObj, "sm_unbanspray", ADMFLAG_GENERIC);
}

public void OnLibraryRemoved(const char[] sLibraryName)
{
	if (StrEqual(sLibraryName, "adminmenu"))
		delete g_hTopMenu;
}

public void TopMenu_Main_Handler(Handle hMenu, TopMenuAction hAction, TopMenuObject hObjID, int iParam1, char[] sBuffer, int iBufflen)
{
	if (hAction == TopMenuAction_DisplayOption)
		Format(sBuffer, iBufflen, "%s", "SprayManager Commands", iParam1);
	else if (hAction == TopMenuAction_DisplayTitle)
		Format(sBuffer, iBufflen, "%s", "SprayManager Commands:", iParam1);
}

public void Handler_SprayBanList(Handle hMenu, TopMenuAction hAction, TopMenuObject hObjID, int iParam1, char[] sBuffer, int iBufflen)
{
	if (hAction == TopMenuAction_DisplayOption)
		Format(sBuffer, iBufflen, "%s", "List Spray Banned Clients", iParam1);
	else if (hAction == TopMenuAction_SelectOption)
		Menu_ListBans(iParam1);
}

public void Handler_TraceSpray(Handle hMenu, TopMenuAction hAction, TopMenuObject hObjID, int iParam1, char[] sBuffer, int iBufflen)
{
	if (hAction == TopMenuAction_DisplayOption)
	{
		Format(sBuffer, iBufflen, "%s", "Trace a Spray", iParam1);
	}
	else if (hAction == TopMenuAction_SelectOption)
	{
		float vecEndPos[3];

		if (TracePlayerAngles(iParam1, vecEndPos))
		{
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsPointInsideAABB(vecEndPos, g_SprayAABB[i]))
				{
					g_bInvokedThroughTopMenu[iParam1] = true;
					Menu_Trace(iParam1, i);

					return;
				}
			}
		}

		PrintToChat(iParam1, "\x01\x04[SprayManager]\x01 Trace did not hit any sprays.");

		if (g_hTopMenu != INVALID_HANDLE)
			DisplayTopMenu(g_hTopMenu, iParam1, TopMenuPosition_LastCategory);
	}
}

public void Handler_Spray(Handle hMenu, TopMenuAction hAction, TopMenuObject hObjID, int iParam1, char[] sBuffer, int iBufflen)
{
	if (hAction == TopMenuAction_DisplayOption)
		Format(sBuffer, iBufflen, "%s", "Spray a Client's Spray", iParam1);
	else if (hAction == TopMenuAction_SelectOption)
		Menu_Spray(iParam1);
}

public void Handler_SprayBan(Handle hMenu, TopMenuAction hAction, TopMenuObject hObjID, int iParam1, char[] sBuffer, int iBufflen)
{
	if (hAction == TopMenuAction_DisplayOption)
		Format(sBuffer, iBufflen, "%s", "Spray Ban a Client", iParam1);
	else if (hAction == TopMenuAction_SelectOption)
		Menu_SprayBan(iParam1);
}

public void Handler_SprayUnban(Handle hMenu, TopMenuAction hAction, TopMenuObject hObjID, int iParam1, char[] sBuffer, int iBufflen)
{
	if (hAction == TopMenuAction_DisplayOption)
		Format(sBuffer, iBufflen, "%s", "Spray Unban a Client", iParam1);
	else if (hAction == TopMenuAction_SelectOption)
		Menu_SprayUnban(iParam1);
}

public void Handler_BanSpray(Handle hMenu, TopMenuAction hAction, TopMenuObject hObjID, int iParam1, char[] sBuffer, int iBufflen)
{
	if (hAction == TopMenuAction_DisplayOption)
		Format(sBuffer, iBufflen, "%s", "Ban a Client's Spray", iParam1);
	else if (hAction == TopMenuAction_SelectOption)
		Menu_BanSpray(iParam1);
}

public void Handler_UnbanSpray(Handle hMenu, TopMenuAction hAction, TopMenuObject hObjID, int iParam1, char[] sBuffer, int iBufflen)
{
	if (hAction == TopMenuAction_DisplayOption)
		Format(sBuffer, iBufflen, "%s", "Unban a Client's Spray", iParam1);
	else if (hAction == TopMenuAction_SelectOption)
		Menu_UnbanSpray(iParam1);
}

void Menu_ListBans(int client)
{
	if (!IsValidClient(client))
		return;

	int iBannedClients;

	Menu ListMenu = new Menu(MenuHandler_Menu_ListBans);
	ListMenu.SetTitle("[SprayManager] Banned Clients:");
	ListMenu.ExitBackButton =  true;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i))
			continue;

		if (g_bSprayBanned[i] || g_bSprayHashBanned[i])
		{
			char sUserID[16];
			char sBuff[64];
			int iUserID = GetClientUserId(i);

			Format(sBuff, sizeof(sBuff), "%N (#%i)", i, iUserID);
			Format(sUserID, sizeof(sUserID), "%d", iUserID);

			ListMenu.AddItem(sUserID, sBuff);
			iBannedClients++;
		}
	}

	if (!iBannedClients)
		ListMenu.AddItem("", "No Banned Clients.", ITEMDRAW_DISABLED);

	ListMenu.Display(client, MENU_TIME_FOREVER);
}

int MenuHandler_Menu_ListBans(Menu hMenu, MenuAction action, int iParam1, int iParam2)
{
	switch (action)
	{
		case MenuAction_End:
			CloseHandle(hMenu);

		case MenuAction_Cancel:
		{
			if (iParam2 == MenuCancel_ExitBack && g_hTopMenu != INVALID_HANDLE)
				DisplayTopMenu(g_hTopMenu, iParam1, TopMenuPosition_LastCategory);
		}

		case MenuAction_Select:
		{
			char sOption[32];
			hMenu.GetItem(iParam2, sOption, sizeof(sOption));

			int target = GetClientOfUserId(StringToInt(sOption));

			if (!IsValidClient(target))
			{
				PrintToChat(iParam1, "\x01\x04[SprayManager]\x01 Target no longer available.");

				if (g_hTopMenu != INVALID_HANDLE)
					DisplayTopMenu(g_hTopMenu, iParam1, TopMenuPosition_LastCategory);
				else
					CloseHandle(hMenu);
			}
			else
			{
				g_bInvokedThroughListMenu[iParam1] = true;
				Menu_ListBans_Target(iParam1, target);
			}
		}
	}
}

void Menu_Trace(int client, int target)
{
	char sSteamID[32];
	GetClientAuthId(target, AuthId_Steam2, sSteamID, sizeof(sSteamID));

	Menu TraceMenu = new Menu(MenuHandler_Menu_Trace);
	TraceMenu.SetTitle("Sprayed by: %N (%s)", target, sSteamID);

	if (g_bInvokedThroughTopMenu[client])
		TraceMenu.ExitBackButton = true;

	TraceMenu.AddItem("1", "Warn Client");
	TraceMenu.AddItem("2", "Slap and Warn Client");
	TraceMenu.AddItem("3", "Kick Client");
	TraceMenu.AddItem("4", "Spray Ban Client");
	TraceMenu.AddItem("5", "Ban Clients Spray");
	TraceMenu.AddItem("", "", ITEMDRAW_SPACER);
	TraceMenu.AddItem("6", "Ban Client");

	g_iSprayTraceTarget[client] = target;

	TraceMenu.Display(client, MENU_TIME_FOREVER);
}

int MenuHandler_Menu_Trace(Menu hMenu, MenuAction action, int iParam1, int iParam2)
{
	switch (action)
	{
		case MenuAction_End:
			CloseHandle(hMenu);

		case MenuAction_Cancel:
		{
			if (iParam2 == MenuCancel_ExitBack && g_hTopMenu != INVALID_HANDLE)
				DisplayTopMenu(g_hTopMenu, iParam1, TopMenuPosition_LastCategory);
		}

		case MenuAction_Select:
		{
			char sOption[2];
			hMenu.GetItem(iParam2, sOption, sizeof(sOption));

			int target = g_iSprayTraceTarget[iParam1];

			if (!IsValidClient(target))
			{
				PrintToChat(iParam1, "\x01\x04[SprayManager]\x01 Target no longer available.");

				g_bInvokedThroughTopMenu[iParam1] = false;

				if (g_hTopMenu != INVALID_HANDLE)
					DisplayTopMenu(g_hTopMenu, iParam1, TopMenuPosition_LastCategory);
				else
					CloseHandle(hMenu);
			}
			else
			{
				switch (StringToInt(sOption))
				{
					case 1:
					{
						PrintToChat(target, "\x01\x04[SprayManager]\x01 Your spray is not allowed, change it.");
						Menu_Trace(iParam1, target);
					}

					case 2:
					{
						SlapPlayer(target, 0);
						PrintToChat(target, "\x01\x04[SprayManager]\x01 Your spray is not allowed, change it.");
						Menu_Trace(iParam1, target);
					}

					case 3:
					{
						g_bInvokedThroughTopMenu[iParam1] = false;
						KickClient(target, "Your spray is not allowed, change it");
					}

					case 4:
					{
						Menu TraceSpraySprayBan = new Menu(MenuHandler_Menu_Trace_SprayBan);
						TraceSpraySprayBan.SetTitle("[SprayManager] Select a Spray Ban Length for %N (#%i)", target, GetClientUserId(target));
						TraceSpraySprayBan.ExitBackButton = true;

						TraceSpraySprayBan.AddItem("10", "10 Minutes");
						TraceSpraySprayBan.AddItem("30", "30 Minutes");
						TraceSpraySprayBan.AddItem("60", "1 Hour");
						TraceSpraySprayBan.AddItem("1440", "1 Day");
						TraceSpraySprayBan.AddItem("10080", "1 Week");
						TraceSpraySprayBan.AddItem("40320", "1 Month");
						TraceSpraySprayBan.AddItem("0", "Permanent");

						g_iSprayBanTarget[iParam1] = target;

						TraceSpraySprayBan.Display(iParam1, MENU_TIME_FOREVER);
					}

					case 5:
					{
						if (BanClientSpray(target))
							PrintToChatAll("\x01\x04[SprayManager] %N\x01 banned \x04%N\x01's spray.", iParam1, target);
						else
							PrintToChat(iParam1, "\x01\x04[SprayManager] %N\x01's spray is already blacklisted.", target);
					}

					case 6:
					{
						Menu TraceSprayBan = new Menu(MenuHandler_Menu_Trace_Ban);
						TraceSprayBan.SetTitle("[SprayManager] Select a Ban Length for %N (#%i)", target, GetClientUserId(target));
						TraceSprayBan.ExitBackButton = true;

						TraceSprayBan.AddItem("10", "10 Minutes");
						TraceSprayBan.AddItem("30", "30 Minutes");
						TraceSprayBan.AddItem("60", "1 Hour");
						TraceSprayBan.AddItem("1440", "1 Day");
						TraceSprayBan.AddItem("10080", "1 Week");
						TraceSprayBan.AddItem("40320", "1 Month");
						TraceSprayBan.AddItem("0", "Permanent");

						g_iBanTarget[iParam1] = target;

						TraceSprayBan.Display(iParam1, MENU_TIME_FOREVER);
					}
				}
			}
		}
	}
}

int MenuHandler_Menu_Trace_SprayBan(Menu hMenu, MenuAction action, int iParam1, int iParam2)
{
	switch (action)
	{
		case MenuAction_End:
			CloseHandle(hMenu);

		case MenuAction_Cancel:
		{
			if (iParam2 == MenuCancel_ExitBack)
			{
				if (IsValidClient(g_iSprayBanTarget[iParam1]))
				{
					Menu_Trace(iParam1, g_iSprayBanTarget[iParam1]);
				}
				else if (g_hTopMenu != INVALID_HANDLE)
				{
					g_bInvokedThroughTopMenu[iParam1] = false;
					DisplayTopMenu(g_hTopMenu, iParam1, TopMenuPosition_LastCategory);
				}
				else
				{
					g_bInvokedThroughTopMenu[iParam1] = false;
					CloseHandle(hMenu);
				}
			}
		}

		case MenuAction_Select:
		{
			char sOption[8];
			hMenu.GetItem(iParam2, sOption, sizeof(sOption));

			int target = g_iSprayBanTarget[iParam1];

			if (!IsValidClient(target))
			{
				PrintToChat(iParam1, "\x01\x04[SprayManager]\x01 Target no longer available.");

				g_iSprayBanTarget[iParam1] = 0;
				g_bInvokedThroughTopMenu[iParam1] = false;

				if (g_hTopMenu != INVALID_HANDLE)
					DisplayTopMenu(g_hTopMenu, iParam1, TopMenuPosition_LastCategory);
				else
					CloseHandle(hMenu);
			}
			else
			{
				if (SprayBanClient(iParam1, target, StringToInt(sOption), "Inappropriate Spray"))
					PrintToChatAll("\x01\x04[SprayManager] %N\x01 spray banned \x04%N\x01.", iParam1, target);

				g_iSprayBanTarget[iParam1] = 0;
				g_bInvokedThroughTopMenu[iParam1] = false;
			}
		}
	}
}

int MenuHandler_Menu_Trace_Ban(Menu hMenu, MenuAction action, int iParam1, int iParam2)
{
	switch (action)
	{
		case MenuAction_End:
			CloseHandle(hMenu);

		case MenuAction_Cancel:
		{
			if (iParam2 == MenuCancel_ExitBack)
			{
				if (IsValidClient(g_iBanTarget[iParam1]))
				{
					Menu_Trace(iParam1, g_iBanTarget[iParam1]);
				}
				else if (g_hTopMenu != INVALID_HANDLE)
				{
					g_bInvokedThroughTopMenu[iParam1] = false;
					DisplayTopMenu(g_hTopMenu, iParam1, TopMenuPosition_LastCategory);
				}
				else
				{
					g_bInvokedThroughTopMenu[iParam1] = false;
					CloseHandle(hMenu);
				}
			}
		}

		case MenuAction_Select:
		{
			char sOption[8];
			hMenu.GetItem(iParam2, sOption, sizeof(sOption));

			int target = g_iBanTarget[iParam1];

			if (!IsValidClient(target))
			{
				PrintToChat(iParam1, "\x01\x04[SprayManager]\x01 Target no longer available.");

				g_iBanTarget[iParam1] = 0;
				g_bInvokedThroughTopMenu[iParam1] = false;

				if (g_hTopMenu != INVALID_HANDLE)
					DisplayTopMenu(g_hTopMenu, iParam1, TopMenuPosition_LastCategory);
				else
					CloseHandle(hMenu);
			}
			else
			{
				FakeClientCommandEx(iParam1, "sm_ban \"#%i\" \"%s\" \"Inappropriate spray\"", GetClientUserId(g_iBanTarget[iParam1]), sOption);
				g_iBanTarget[iParam1] = 0;
				g_bInvokedThroughTopMenu[iParam1] = false;
			}
		}
	}
}

void Menu_Spray(int client)
{
	if (!IsValidClient(client))
		return;

	Menu SprayMenu = new Menu(MenuHandler_Menu_Spray);
	SprayMenu.SetTitle("[SprayManager] Select a Client to Force Spray:");
	SprayMenu.ExitBackButton =  true;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i) || IsFakeClient(i))
			continue;

		char sUserID[16];
		char sBuff[64];
		int iUserID = GetClientUserId(i);

		Format(sUserID, sizeof(sUserID), "%d", iUserID);

		if (g_bSprayBanned[i] && g_bSprayHashBanned[i])
		{
			Format(sBuff, sizeof(sBuff), "%N (#%i) [Spray & Hash Banned]", i, iUserID);

			SprayMenu.AddItem(sUserID, sBuff);
		}
		else if (g_bSprayBanned[i])
		{
			Format(sBuff, sizeof(sBuff), "%N (#%i) [Spray Banned]", i, iUserID);

			SprayMenu.AddItem(sUserID, sBuff);
		}
		else if (g_bSprayHashBanned[i])
		{
			Format(sBuff, sizeof(sBuff), "%N (#%i) [Hash Banned]", i, iUserID);

			SprayMenu.AddItem(sUserID, sBuff);
		}
		else
		{
			Format(sBuff, sizeof(sBuff), "%N (#%i)", i, iUserID);

			SprayMenu.AddItem(sUserID, sBuff);
		}
	}

	SprayMenu.Display(client, MENU_TIME_FOREVER);
}

int MenuHandler_Menu_Spray(Menu hMenu, MenuAction action, int iParam1, int iParam2)
{
	switch (action)
	{
		case MenuAction_End:
			CloseHandle(hMenu);

		case MenuAction_Cancel:
		{
			if (iParam2 == MenuCancel_ExitBack && g_hTopMenu != INVALID_HANDLE)
				DisplayTopMenu(g_hTopMenu, iParam1, TopMenuPosition_LastCategory);
		}

		case MenuAction_Select:
		{
			char sOption[8];
			hMenu.GetItem(iParam2, sOption, sizeof(sOption));

			int target = GetClientOfUserId(StringToInt(sOption));

			if (!IsValidClient(target))
			{
				PrintToChat(iParam1, "\x01\x04[SprayManager]\x01 Target no longer available.");

				if (g_hTopMenu != INVALID_HANDLE)
					DisplayTopMenu(g_hTopMenu, iParam1, TopMenuPosition_LastCategory);
				else
					CloseHandle(hMenu);
			}
			else
			{
				g_bAllowSpray = true;
				ForceSpray(iParam1, target);

				PrintToChat(iParam1, "\x01\x04[SprayManager]\x01 Sprayed \x04%N\x01's spray(s).", target);

				Menu_Spray(iParam1);
			}
		}
	}
}

void Menu_SprayBan(int client)
{
	if (!IsValidClient(client))
		return;

	Menu SprayBanMenu = new Menu(MenuHandler_Menu_SprayBan);
	SprayBanMenu.SetTitle("[SprayManager] Select a Client to Spray Ban:");
	SprayBanMenu.ExitBackButton = true;

	int iClientsToDisplay;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && !g_bSprayBanned[i])
		{
			char sUserID[16];
			char sBuff[64];
			int iUserID = GetClientUserId(i);

			Format(sBuff, sizeof(sBuff), "%N (#%i)", i, iUserID);
			Format(sUserID, sizeof(sUserID), "%d", iUserID);

			SprayBanMenu.AddItem(sUserID, sBuff);
			iClientsToDisplay++;
		}
	}

	if (!iClientsToDisplay)
		SprayBanMenu.AddItem("", "No Clients to Display.", ITEMDRAW_DISABLED);

	SprayBanMenu.Display(client, MENU_TIME_FOREVER);
}

int MenuHandler_Menu_SprayBan(Menu hMenu, MenuAction action, int iParam1, int iParam2)
{
	switch (action)
	{
		case MenuAction_End:
			CloseHandle(hMenu);

		case MenuAction_Cancel:
		{
			if (iParam2 == MenuCancel_ExitBack && g_hTopMenu != INVALID_HANDLE)
				DisplayTopMenu(g_hTopMenu, iParam1, TopMenuPosition_LastCategory);
		}

		case MenuAction_Select:
		{
			char sOption[32];
			hMenu.GetItem(iParam2, sOption, sizeof(sOption));

			int target = GetClientOfUserId(StringToInt(sOption));

			if (!IsValidClient(target))
			{
				PrintToChat(iParam1, "\x01\x04[SprayManager]\x01 Target no longer available.");

				if (g_hTopMenu != INVALID_HANDLE)
					DisplayTopMenu(g_hTopMenu, iParam1, TopMenuPosition_LastCategory);
				else
					CloseHandle(hMenu);
			}
			else
			{
				Menu SprayBanLengthMenu = new Menu(MenuHandler_Menu_SprayBan_Length);
				SprayBanLengthMenu.SetTitle("[SprayManager] Choose a Spray Ban Length for %N (#%i)", target, GetClientUserId(target));
				SprayBanLengthMenu.ExitBackButton = true;

				SprayBanLengthMenu.AddItem("10", "10 Minutes");
				SprayBanLengthMenu.AddItem("30", "30 Minutes");
				SprayBanLengthMenu.AddItem("60", "1 Hour");
				SprayBanLengthMenu.AddItem("1440", "1 Day");
				SprayBanLengthMenu.AddItem("10080", "1 Week");
				SprayBanLengthMenu.AddItem("40320", "1 Month");
				SprayBanLengthMenu.AddItem("0", "Permanent");

				g_iSprayBanTarget[iParam1] = target;

				SprayBanLengthMenu.Display(iParam1, MENU_TIME_FOREVER);
			}
		}
	}
}

int MenuHandler_Menu_SprayBan_Length(Menu hMenu, MenuAction action, int iParam1, int iParam2)
{
	switch (action)
	{
		case MenuAction_End:
			CloseHandle(hMenu);

		case MenuAction_Cancel:
		{
			if (iParam2 == MenuCancel_ExitBack)
				Menu_SprayBan(iParam1);
		}

		case MenuAction_Select:
		{
			char sOption[8];
			hMenu.GetItem(iParam2, sOption, sizeof(sOption));

			int target = g_iSprayBanTarget[iParam1];

			if (!IsValidClient(target))
			{
				PrintToChat(iParam1, "\x01\x04[SprayManager]\x01 Target no longer available.");

				g_iSprayBanTarget[iParam1] = 0;

				Menu_SprayBan(iParam1);
			}
			else
			{
				if (SprayBanClient(iParam1, target, StringToInt(sOption), "Inappropriate Spray"))
					PrintToChatAll("\x01\x04[SprayManager] %N\x01 spray banned \x04%N\x01.", iParam1, target);

				g_iSprayBanTarget[iParam1] = 0;
			}
		}
	}
}

void Menu_SprayUnban(int client)
{
	if (!IsValidClient(client))
		return;

	int iBannedClients;

	Menu SprayUnbanMenu = new Menu(MenuHandler_Menu_SprayUnban);
	SprayUnbanMenu.SetTitle("[SprayManager] Select a Client to Unban:");
	SprayUnbanMenu.ExitBackButton =  true;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i))
			continue;

		if (g_bSprayBanned[i] || g_bSprayHashBanned[i])
		{
			char sUserID[16];
			char sBuff[64];
			int iUserID = GetClientUserId(i);

			Format(sBuff, sizeof(sBuff), "%N (#%i)", i, iUserID);
			Format(sUserID, sizeof(sUserID), "%d", iUserID);

			SprayUnbanMenu.AddItem(sUserID, sBuff);
			iBannedClients++;
		}
	}

	if (!iBannedClients)
		SprayUnbanMenu.AddItem("", "No Banned Clients.", ITEMDRAW_DISABLED);

	SprayUnbanMenu.Display(client, MENU_TIME_FOREVER);
}

int MenuHandler_Menu_SprayUnban(Menu hMenu, MenuAction action, int iParam1, int iParam2)
{
	switch (action)
	{
		case MenuAction_End:
			CloseHandle(hMenu);

		case MenuAction_Cancel:
		{
			if (iParam2 == MenuCancel_ExitBack && g_hTopMenu != INVALID_HANDLE)
				DisplayTopMenu(g_hTopMenu, iParam1, TopMenuPosition_LastCategory);
		}

		case MenuAction_Select:
		{
			char sOption[32];
			hMenu.GetItem(iParam2, sOption, sizeof(sOption));

			int target = GetClientOfUserId(StringToInt(sOption));

			if (!IsValidClient(target))
			{
				PrintToChat(iParam1, "\x01\x04[SprayManager]\x01 Target no longer available.");

				g_iSprayUnbanTarget[iParam1] = 0;

				Menu_SprayUnban(iParam1);
			}
			else
			{
				g_bInvokedThroughListMenu[iParam1] = false;
				Menu_ListBans_Target(iParam1, target);
			}
		}
	}
}

void Menu_BanSpray(int client)
{
	if (!IsValidClient(client))
		return;

	int iClientsToDisplay;

	Menu BanSprayMenu = new Menu(MenuHandler_Menu_BanSpray);
	BanSprayMenu.SetTitle("[SprayManager] Select a Client to Ban their Spray:");
	BanSprayMenu.ExitBackButton =  true;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && !g_bSprayHashBanned[i])
		{
			char sUserID[16];
			char sBuff[64];
			int iUserID = GetClientUserId(i);

			Format(sBuff, sizeof(sBuff), "%N (#%i)", i, iUserID);
			Format(sUserID, sizeof(sUserID), "%d", iUserID);

			BanSprayMenu.AddItem(sUserID, sBuff);
			iClientsToDisplay++;
		}
	}

	if (!iClientsToDisplay)
		BanSprayMenu.AddItem("", "No Clients to Display.", ITEMDRAW_DISABLED);

	BanSprayMenu.Display(client, MENU_TIME_FOREVER);
}

int MenuHandler_Menu_BanSpray(Menu hMenu, MenuAction action, int iParam1, int iParam2)
{
	switch (action)
	{
		case MenuAction_End:
			CloseHandle(hMenu);

		case MenuAction_Cancel:
		{
			if (iParam2 == MenuCancel_ExitBack && g_hTopMenu != INVALID_HANDLE)
				DisplayTopMenu(g_hTopMenu, iParam1, TopMenuPosition_LastCategory);
		}

		case MenuAction_Select:
		{
			char sOption[32];
			hMenu.GetItem(iParam2, sOption, sizeof(sOption));

			int target = GetClientOfUserId(StringToInt(sOption));

			if (!IsValidClient(target))
			{
				PrintToChat(iParam1, "\x01\x04[SprayManager]\x01 Target no longer available.");

				Menu_BanSpray(iParam1);
			}
			else
			{
				if (BanClientSpray(target))
					PrintToChatAll("\x01\x04[SprayManager] %N\x01 banned \x04%N\x01's spray.", iParam1, target);
				else
					PrintToChat(iParam1, "\x01\x04[SprayManager] %N\x01's spray is already blacklisted.", target);
			}
		}
	}
}

void Menu_UnbanSpray(int client)
{
	if (!IsValidClient(client))
		return;

	Menu UnbanSprayMenu = new Menu(MenuHandler_Menu_UnbanSpray);
	UnbanSprayMenu.SetTitle("[SprayManager] Select a Client to Unban their Spray:");
	UnbanSprayMenu.ExitBackButton =  true;

	int iBannedClients;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && g_bSprayHashBanned[i])
		{
			char sUserID[16];
			char sBuff[64];
			int iUserID = GetClientUserId(i);

			Format(sBuff, sizeof(sBuff), "%N (#%i)", i, iUserID);
			Format(sUserID, sizeof(sUserID), "%d", iUserID);

			UnbanSprayMenu.AddItem(sUserID, sBuff);
			iBannedClients++;
		}
	}

	if (!iBannedClients)
		UnbanSprayMenu.AddItem("", "No Banned Clients.", ITEMDRAW_DISABLED);

	UnbanSprayMenu.Display(client, MENU_TIME_FOREVER);
}

int MenuHandler_Menu_UnbanSpray(Menu hMenu, MenuAction action, int iParam1, int iParam2)
{
	switch (action)
	{
		case MenuAction_End:
			CloseHandle(hMenu);

		case MenuAction_Cancel:
		{
			if (iParam2 == MenuCancel_ExitBack && g_hTopMenu != INVALID_HANDLE)
				DisplayTopMenu(g_hTopMenu, iParam1, TopMenuPosition_LastCategory);
		}

		case MenuAction_Select:
		{
			char sOption[32];
			hMenu.GetItem(iParam2, sOption, sizeof(sOption));

			int target = GetClientOfUserId(StringToInt(sOption));

			if (!IsValidClient(target))
			{
				PrintToChat(iParam1, "\x01\x04[SprayManager]\x01 Target no longer available.");

				Menu_UnbanSpray(iParam1);
			}
			else
			{
				if (UnbanClientSpray(target))
					PrintToChatAll("\x01\x04[SprayManager] %N\x01 unbanned \x04%N\x01's spray.", iParam1, target);
				else
					PrintToChat(iParam1, "\x01\x04[SprayManager] %N\x01's spray is not blacklisted.", target);
			}
		}
	}
}

void Menu_ListBans_Target(int client, int target)
{
	Menu ListTargetMenu = new Menu(MenuHandler_Menu_ListBans_Target);
	ListTargetMenu.SetTitle("[SprayManager] Banned Client: %N (#%i)", target, GetClientUserId(target));
	ListTargetMenu.ExitBackButton = true;

	char sBanType[32];
	char sUserID[32];
	int iUserID = GetClientUserId(target);

	Format(sUserID, sizeof(sUserID), "%d", iUserID);

	if (g_bSprayHashBanned[target] && !g_bSprayBanned[target])
	{
		strcopy(sBanType, sizeof(sBanType), "Type: Hash");

		ListTargetMenu.AddItem("", sBanType, ITEMDRAW_DISABLED);
		ListTargetMenu.AddItem("", "", ITEMDRAW_SPACER);

		ListTargetMenu.AddItem(sUserID, "Unban Client?");

		ListTargetMenu.Display(client, MENU_TIME_FOREVER);
		return;
	}

	char sBanExpiryDate[64];
	char sBanIssuedDate[64];
	char sBanDuration[64];
	char sBannedBy[128];
	char sBanReason[64];
	int iBanExpiryDate = g_iSprayUnbanTimestamp[target];
	int iBanIssuedDate = g_iSprayBanTimestamp[target];
	int iBanDuration = iBanExpiryDate ? ((iBanExpiryDate - iBanIssuedDate) / 60) : 0;

	if (iBanExpiryDate)
	{
		FormatTime(sBanExpiryDate, sizeof(sBanExpiryDate), NULL_STRING, iBanExpiryDate);
		Format(sBanDuration, sizeof(sBanDuration), "%i %s", iBanDuration, SingularOrMultiple(iBanDuration) ? "Minutes" : "Minute");
	}
	else
	{
		strcopy(sBanExpiryDate, sizeof(sBanExpiryDate), "Never");
		strcopy(sBanDuration, sizeof(sBanDuration), "Permanent");
	}

	FormatTime(sBanIssuedDate, sizeof(sBanIssuedDate), NULL_STRING, iBanIssuedDate);
	Format(sBannedBy, sizeof(sBannedBy), "Banned by: %s (%s)", g_sBanIssuer[target], g_sBanIssuerSID[target]);
	Format(sBanDuration, sizeof(sBanDuration), "Duration: %s", sBanDuration);
	Format(sBanExpiryDate, sizeof(sBanExpiryDate), "Expires: %s", sBanExpiryDate);
	Format(sBanIssuedDate, sizeof(sBanIssuedDate), "Issued on: %s", sBanIssuedDate);
	Format(sBanReason, sizeof(sBanReason), "Reason: %s", g_sBanReason[target]);

	if (g_bSprayBanned[target] && g_bSprayHashBanned[target])
		strcopy(sBanType, sizeof(sBanType), "Type: Spray & Hash");
	else if (g_bSprayBanned[target])
		strcopy(sBanType, sizeof(sBanType), "Type: Spray");

	ListTargetMenu.AddItem("", sBanType, ITEMDRAW_DISABLED);
	ListTargetMenu.AddItem("", sBannedBy, ITEMDRAW_DISABLED);
	ListTargetMenu.AddItem("", sBanIssuedDate, ITEMDRAW_DISABLED);
	ListTargetMenu.AddItem("", sBanExpiryDate, ITEMDRAW_DISABLED);
	ListTargetMenu.AddItem("", sBanDuration, ITEMDRAW_DISABLED);
	ListTargetMenu.AddItem("", sBanReason, ITEMDRAW_DISABLED);

	ListTargetMenu.AddItem(sUserID, "Unban Client?");

	ListTargetMenu.Display(client, MENU_TIME_FOREVER);
}

int MenuHandler_Menu_ListBans_Target(Menu hMenu, MenuAction action, int iParam1, int iParam2)
{
	switch (action)
	{
		case MenuAction_End:
			CloseHandle(hMenu);

		case MenuAction_Cancel:
		{
			if (iParam2 == MenuCancel_ExitBack)
			{
				if (g_bInvokedThroughListMenu[iParam1])
					Menu_ListBans(iParam1);
				else
					Menu_SprayUnban(iParam1);
			}
		}

		case MenuAction_Select:
		{
			char sOption[32];
			hMenu.GetItem(iParam2, sOption, sizeof(sOption));
			int target = GetClientOfUserId(StringToInt(sOption));

			if (!IsValidClient(target))
			{
				PrintToChat(iParam1, "\x01\x04[SprayManager]\x01 Target no longer available.");
				Menu_ListBans(iParam1);
			}
			else
			{
				Menu MenuConfirmUnban = new Menu(MenuHandler_Menu_ConfirmUnban);
				MenuConfirmUnban.SetTitle("[SprayManager] Unban %N?", target);
				MenuConfirmUnban.ExitBackButton = true;

				MenuConfirmUnban.AddItem("Y", "Yes.");
				MenuConfirmUnban.AddItem("N", "No.");

				g_iSprayUnbanTarget[iParam1] = target;

				MenuConfirmUnban.Display(iParam1, MENU_TIME_FOREVER);
			}
		}
	}
}

int MenuHandler_Menu_ConfirmUnban(Menu hMenu, MenuAction action, int iParam1, int iParam2)
{
	switch (action)
	{
		case MenuAction_End:
			CloseHandle(hMenu);

		case MenuAction_Cancel:
		{
			if (iParam2 == MenuCancel_ExitBack)
			{
				if (IsValidClient(g_iSprayUnbanTarget[iParam1]))
					Menu_ListBans_Target(iParam1, g_iSprayUnbanTarget[iParam1]);
				else if (g_hTopMenu != INVALID_HANDLE)
					DisplayTopMenu(g_hTopMenu, iParam1, TopMenuPosition_LastCategory);
				else
					CloseHandle(hMenu);
			}
		}

		case MenuAction_Select:
		{
			char sOption[2];
			hMenu.GetItem(iParam2, sOption, sizeof(sOption));

			int target = g_iSprayUnbanTarget[iParam1];

			if (!IsValidClient(target))
			{
				PrintToChat(iParam1, "\x01\x04[SprayManager]\x01 Target no longer available.");

				g_iSprayUnbanTarget[iParam1] = 0;

				if (g_hTopMenu != INVALID_HANDLE)
					DisplayTopMenu(g_hTopMenu, iParam1, TopMenuPosition_LastCategory);
				else
					CloseHandle(hMenu);
			}
			else
			{
				if (sOption[0] == 'Y')
				{
					if (g_bSprayHashBanned[target] && g_bSprayBanned[target])
					{
						PrintToChatAll("\x01\x04[SprayManager] %N\x01 spray unbanned \x04%N\x01.", iParam1, target);
						SprayUnbanClient(target);
						UnbanClientSpray(target);
					}
					else if (g_bSprayBanned[target])
					{
						PrintToChatAll("\x01\x04[SprayManager] %N\x01 spray unbanned \x04%N\x01.", iParam1, target);
						SprayUnbanClient(target);
					}
					else if (g_bSprayHashBanned[target])
					{
						PrintToChatAll("\x01\x04[SprayManager] %N\x01 unbanned \x04%N\x01's spray.", iParam1, target);
						UnbanClientSpray(target);
					}

					g_iSprayUnbanTarget[iParam1] = 0;
				}
				else if (sOption[0] == 'N')
				{
					Menu_ListBans_Target(iParam1, g_iSprayUnbanTarget[iParam1]);
					g_iSprayUnbanTarget[iParam1] = 0;
				}
			}
		}
	}
}

public Action Command_AdminSpray(int client, int argc)
{
	if (!client)
	{
		PrintToServer("[SprayManager] Cannot use command from server console.");
		return Plugin_Handled;
	}

	if (argc > 0)
	{
		char sArgs[64];
		char sTargetName[MAX_TARGET_LENGTH];
		int iTargets[MAXPLAYERS];
		int iTargetCount;
		bool bIsML;

		GetCmdArg(1, sArgs, sizeof(sArgs));

		if ((iTargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS, COMMAND_FILTER_NO_BOTS, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
		{
			ReplyToTargetError(client, iTargetCount);
			return Plugin_Handled;
		}

		for (int i = 0; i < iTargetCount; i++)
		{
			g_bAllowSpray = true;
			ForceSpray(client, iTargets[i]);
		}

		PrintToChat(client, "\x01\x04[SprayManager]\x01 Sprayed \x04%s\x01's spray(s).", sTargetName);

		return Plugin_Handled;
	}

	float vecEndPos[3];
	TracePlayerAngles(client, vecEndPos);

	g_bAllowSpray = true;
	ForceSpray(client, client);

	PrintToChat(client, "\x01\x04[SprayManager]\x01 Sprayed your own spray.");

	return Plugin_Handled;
}

public Action Command_SprayBan(int client, int argc)
{
	if (argc < 1)
	{
		ReplyToCommand(client, "[SprayManager] Usage: sm_sprayban <target> <time:optional> <reason:optional>");
		return Plugin_Handled;
	}

	int iTarget;
	char sTarget[32];
	char sLength[32];
	char sReason[32];

	GetCmdArg(1, sTarget, sizeof(sTarget));

	if (argc > 1)
	{
		GetCmdArg(2, sLength, sizeof(sLength));

		if (argc > 2)
			GetCmdArg(3, sReason, sizeof(sReason));
	}

	if (!(iTarget = FindTarget(client, sTarget)))
		return Plugin_Handled;

	if (SprayBanClient(client, iTarget, StringToInt(sLength), sReason))
		PrintToChatAll("\x01\x04[SprayManager] %N\x01 spray banned \x04%N\x01.", client, iTarget);

	return Plugin_Handled;
}

public Action Command_SprayUnban(int client, int argc)
{
	if (argc < 1)
	{
		ReplyToCommand(client, "[SprayManager] Usage: sm_sprayunban <target>");
		return Plugin_Handled;
	}

	int iTarget;
	char sTarget[32];

	GetCmdArg(1, sTarget, sizeof(sTarget));

	if (!(iTarget = FindTarget(client, sTarget)))
		return Plugin_Handled;

	if (!SprayUnbanClient(iTarget))
	{
		ReplyToCommand(client, "[SprayManager] %N is not spray banned.", iTarget);
		return Plugin_Handled;
	}

	PrintToChatAll("\x01\x04[SprayManager] %N\x01 spray unbanned \x04%N\x01.", client, iTarget);

	return Plugin_Handled;
}

public Action Command_BanSpray(int client, int argc)
{
	if (argc < 1)
	{
		ReplyToCommand(client, "[SprayManager] Usage: sm_banspray <target>");
		return Plugin_Handled;
	}

	int iTarget;
	char sTarget[32];

	GetCmdArg(1, sTarget, sizeof(sTarget));

	if (!(iTarget = FindTarget(client, sTarget)))
		return Plugin_Handled;

	if (!BanClientSpray(iTarget))
	{
		ReplyToCommand(client, "[SprayManager] %N's spray is already blacklisted.", iTarget);
		return Plugin_Handled;
	}

	PrintToChatAll("\x01\x04[SprayManager] %N\x01 banned \x04%N\x01's spray.", client, iTarget);

	return Plugin_Handled;
}

public Action Command_UnbanSpray(int client, int argc)
{
	if (argc < 1)
	{
		ReplyToCommand(client, "[SprayManager] Usage: sm_unbanspray <target>");
		return Plugin_Handled;
	}

	int iTarget;
	char sTarget[32];

	GetCmdArg(1, sTarget, sizeof(sTarget));

	if (!(iTarget = FindTarget(client, sTarget)))
		return Plugin_Handled;

	if (!UnbanClientSpray(iTarget))
	{
		ReplyToCommand(client, "[SprayManager] %N's spray is not blacklisted.", iTarget);
		return Plugin_Handled;
	}

	PrintToChatAll("\x01\x04[SprayManager] %N\x01 unbanned \x04%N\x01's spray.", client, iTarget);

	return Plugin_Handled;
}

public Action Command_TraceSpray(int client, int argc)
{
	if (!client)
	{
		PrintToServer("[SprayManager] Cannot use command from server console.");
		return Plugin_Handled;
	}

	float vecEndPos[3];
	if (TracePlayerAngles(client, vecEndPos))
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsPointInsideAABB(vecEndPos, g_SprayAABB[i]))
			{
				g_bInvokedThroughTopMenu[client] = false;
				Menu_Trace(client, i);

				return Plugin_Handled;
			}
		}
	}

	PrintToChat(client, "\x01\x04[SprayManager]\x01 Trace did not hit any sprays.");

	return Plugin_Handled;
}

public Action Command_RemoveSpray(int client, int argc)
{
	if (!client)
	{
		PrintToServer("[SprayManager] Cannot use command from server console.");
		return Plugin_Handled;
	}

	if (argc > 0)
	{
		char sArgs[64];
		char sTargetName[MAX_TARGET_LENGTH];
		int iTargets[MAXPLAYERS];
		int iTargetCount;
		bool bIsML;

		GetCmdArg(1, sArgs, sizeof(sArgs));

		if ((iTargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS, COMMAND_FILTER_NO_BOTS, sTargetName, sizeof(sTargetName), bIsML)) <= 0)
		{
			ReplyToTargetError(client, iTargetCount);
			return Plugin_Handled;
		}

		for (int i = 0; i < iTargetCount; i++)
		{
			g_bAllowSpray = true;
			SprayClientDecal(iTargets[i], 0, ACTUAL_NULL_VECTOR);
		}

		PrintToChat(client, "\x01\x04[SprayManager]\x01 Removed \x04%s\x01's spray(s).", sTargetName);

		return Plugin_Handled;
	}

	float vecEndPos[3];

	if (TracePlayerAngles(client, vecEndPos))
	{
	 	for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsPointInsideAABB(vecEndPos, g_SprayAABB[i]))
				continue;

			g_bAllowSpray = true;
			SprayClientDecal(i, 0, ACTUAL_NULL_VECTOR);

			PrintToChat(client, "\x01\x04[SprayManager]\x01 Removed \x04%N\x01's spray.", i);

			return Plugin_Handled;
		}
	}

	PrintToChat(client, "\x01\x04[SprayManager]\x01 No spray could be found.");

	return Plugin_Handled;
}

public Action Command_SprayManager_UpdateInfo(int client, int argc)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			UpdatePlayerInfo(i);
			UpdateSprayHashInfo(i);
		}
	}

	ReplyToCommand(client, "[SprayManager] Refreshed database.");
}

public Action HookDecal(const char[] sTEName, const int[] iClients, int iNumClients, float fSendDelay)
{
	int client = TE_ReadNum("m_nPlayer");

	if (!IsValidClient(client))
		return Plugin_Continue;

	float vecOrigin[3];
	float AABBTemp[AABBTotalPoints];

	TE_ReadVector("m_vecOrigin", vecOrigin);

	AABBTemp[AABBMinX] = vecOrigin[0] - 32.0;
	AABBTemp[AABBMaxX] = vecOrigin[0] + 32.0;
	AABBTemp[AABBMinY] = vecOrigin[1] - 32.0;
	AABBTemp[AABBMaxY] = vecOrigin[1] + 32.0;
	AABBTemp[AABBMinZ] = vecOrigin[2] - 32.0;
	AABBTemp[AABBMaxZ] = vecOrigin[2] + 32.0;

	if (!g_bAllowSpray)
	{
		if (g_bSprayHashBanned[client])
		{
			PrintToChat(client, "\x01\x04[SprayManager]\x01 Your spray is blacklisted, change it.");
			return Plugin_Handled;
		}

		if (g_iSprayUnbanTimestamp[client] != 0 && g_iSprayUnbanTimestamp[client] != -1)
		{
			if (g_iSprayUnbanTimestamp[client] < GetTime())
				SprayUnbanClient(client);
		}

		if (g_bSprayBanned[client])
		{
			char sRemainingTime[512];

			FormatRemainingTime(g_iSprayUnbanTimestamp[client], sRemainingTime, sizeof(sRemainingTime));

			PrintToChat(client, "\x01\x04[SprayManager]\x01 You are currently spray banned. (\x04%s\x01)", sRemainingTime);

			return Plugin_Handled;
		}

		if (g_fNextSprayTime[client] > GetGameTime())
			return Plugin_Handled;

		if (!CheckCommandAccess(client, "sm_sprayban", ADMFLAG_GENERIC))
		{
			if (g_cvarUseProximityCheck.IntValue >= 1)
			{
				for (int i = 1; i <= MaxClients; i++)
				{
					if (!IsValidClient(i) || i == client)
						continue;

					if (IsVectorZero(g_vecSprayOrigin[i]))
						continue;

					if (!CheckForAABBCollision(AABBTemp, g_SprayAABB[i]))
						continue;

					if (CheckCommandAccess(i, "", ADMFLAG_CUSTOM1, true) || CheckCommandAccess(i, "sm_sprayban", ADMFLAG_GENERIC))
					{
						PrintToChat(client, "\x01\x04[SprayManager]\x01 Your spray is too close to \x04%N\x01's spray.", i);

						return Plugin_Handled;
					}
				}
			}

			if (CheckCommandAccess(client, "", ADMFLAG_CUSTOM1))
				g_fNextSprayTime[client] = GetGameTime() + (g_cvarDecalFrequency.FloatValue / 2);
			else
				g_fNextSprayTime[client] = GetGameTime() + g_cvarDecalFrequency.FloatValue;
		}
	}

	g_bAllowSpray = false;

	g_iSprayLifetime[client] = 0;

	g_vecSprayOrigin[client][0] = vecOrigin[0];
	g_vecSprayOrigin[client][1] = vecOrigin[1];
	g_vecSprayOrigin[client][2] = vecOrigin[2];

	g_SprayAABB[client][AABBMinX] = AABBTemp[AABBMinX];
	g_SprayAABB[client][AABBMaxX] = AABBTemp[AABBMaxX];
	g_SprayAABB[client][AABBMinY] = AABBTemp[AABBMinY];
	g_SprayAABB[client][AABBMaxY] = AABBTemp[AABBMaxY];
	g_SprayAABB[client][AABBMinZ] = AABBTemp[AABBMinZ];
	g_SprayAABB[client][AABBMaxZ] = AABBTemp[AABBMaxZ];

	ArrayList PosArray = new ArrayList(3, 0);

	PosArray.PushArray(vecOrigin, 3);

	RequestFrame(FrameAfterSpray, PosArray);

	return Plugin_Continue;
}

public void FrameAfterSpray(ArrayList Data)
{
	float vecPos[3];
	Data.GetArray(0, vecPos, 3);

	EmitSoundToAll("player/sprayer.wav", SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, _, _, _, vecPos);

	delete Data;
}

public Action HookSprayer(int iClients[MAXPLAYERS], int &iNumClients, char sSoundName[PLATFORM_MAX_PATH], int &iEntity, int &iChannel, float &flVolume, int &iLevel, int &iPitch, int &iFlags, char sSoundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if (StrEqual(sSoundName, "player/sprayer.wav") && iEntity > 0)
		return Plugin_Handled;

	return Plugin_Continue;
}

public Action PerformPlayerTraces(Handle hTimer)
{
	static bool bLookingatSpray[MAXPLAYERS + 1];
	static bool bOnce[MAXPLAYERS + 1];
	float vecPos[3];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i) || IsFakeClient(i))
			continue;

		if (!TracePlayerAngles(i, vecPos))
			continue;

		for (int a = 1; a <= MaxClients; a++)
		{
			if (!IsValidClient(a))
				continue;

			if (IsPointInsideAABB(vecPos, g_SprayAABB[a]))
			{
				char sSteamID[32];
				GetClientAuthId(a, AuthId_Steam2, sSteamID, sizeof(sSteamID));

				PrintHintText(i, "Sprayed by: %N (%s)", a, sSteamID);
				StopSound(i, SNDCHAN_STATIC, "UI/hint.wav");

				bLookingatSpray[i] = true;
				bOnce[i] = false;

				break;
			}
			else
				bLookingatSpray[i] = false;
		}
	}

	for (int x = 1; x <= MaxClients; x++)
	{
		if (!IsValidClient(x) || IsFakeClient(x))
			continue;

		if (!bLookingatSpray[x] && !bOnce[x])
		{
			PrintHintText(x, "");
			StopSound(x, SNDCHAN_STATIC, "UI/hint.wav");

			bOnce[x] = true;
		}
	}
}

void InitializeSQL()
{
	if (g_hDatabase != null)
		delete g_hDatabase;

	if (SQL_CheckConfig("spraymanager"))
		SQL_TConnect(OnSQLConnected, "spraymanager");
	else
		SetFailState("Could not find \"spraymanager\" entry in databases.cfg.");
}

public void OnSQLConnected(Handle hParent, Handle hChild, const char[] err, any data)
{
	if (hChild == null)
	{
		LogError("Failed to connect to database, retrying in 10 seconds. (%s)", err);

		if (CreateTimer(10.0, ReconnectSQL) == null)
		{
			LogError("Failed to create re-connector timer, trying to reconnect now.");
			InitializeSQL();
		}

		return;
	}

	char sDriver[16];
	g_hDatabase = CloneHandle(hChild);
	SQL_GetDriverIdent(hParent, sDriver, sizeof(sDriver));

	if (!strncmp(sDriver, "my", 2, false))
	{
		SQL_TQuery(g_hDatabase, DummyCallback, "SET NAMES \"UTF8\"");

		SQL_TQuery(g_hDatabase, OnSQLTableCreated, "CREATE TABLE IF NOT EXISTS `spraymanager` (`steamid` VARCHAR(32) NOT NULL, `name` VARCHAR(32) NOT NULL, `unbantime` INT, `issuersteamid` VARCHAR(32), `issuername` VARCHAR(32) NOT NULL, `issuedtime` INT, `issuedreason` VARCHAR(64) NOT NULL, PRIMARY KEY(steamid)) CHARACTER SET utf8 COLLATE utf8_general_ci;");
		SQL_TQuery(g_hDatabase, OnSQLSprayBlacklistCreated, "CREATE TABLE IF NOT EXISTS `sprayblacklist` (`sprayhash` VARCHAR(16) NOT NULL, `sprayer` VARCHAR(32) NOT NULL, `sprayersteamid` VARCHAR(32), PRIMARY KEY(sprayhash)) CHARACTER SET utf8 COLLATE utf8_general_ci;");

		g_bSQLite = false;
	}
	else
	{
		SQL_TQuery(g_hDatabase, OnSQLTableCreated, "CREATE TABLE IF NOT EXISTS `spraymanager` (`steamid` TEXT NOT NULL, `name` TEXT DEFAULT 'unknown', `unbantime` INTEGER, `issuersteamid` TEXT, `issuername` TEXT DEFAULT 'unknown', `issuedtime` INTEGER NOT NULL, `issuedreason` TEXT DEFAULT 'none', PRIMARY KEY(steamid));");
		SQL_TQuery(g_hDatabase, OnSQLSprayBlacklistCreated, "CREATE TABLE IF NOT EXISTS `sprayblacklist` (`sprayhash` TEXT NOT NULL, `sprayer` TEXT DEFAULT 'unknown', `sprayersteamid` TEXT, PRIMARY KEY(sprayhash));");

		g_bSQLite = true;
	}
}

public Action ReconnectSQL(Handle hTimer)
{
	InitializeSQL();

	return Plugin_Handled;
}

public void OnSQLTableCreated(Handle hParent, Handle hChild, const char[] err, any data)
{
	if (hChild == null)
	{
		LogError("Database error while creating/checking for \"spraymanager\" table, retrying in 10 seconds. (%s)", err);

		if (CreateTimer(10.0, RetryMainTableCreation) == null)
		{
			LogError("Failed to create re-query timer, trying to query now.");

			if (g_bSQLite)
				SQL_TQuery(g_hDatabase, OnSQLTableCreated, "CREATE TABLE IF NOT EXISTS `spraymanager` (`steamid` TEXT NOT NULL, `name` TEXT DEFAULT 'unknown', `unbantime` INTEGER, `issuersteamid` TEXT, `issuername` TEXT DEFAULT 'unknown', `issuedtime` INTEGER NOT NULL, `issuedreason` TEXT DEFAULT 'none', PRIMARY KEY(steamid));");
			else
				SQL_TQuery(g_hDatabase, OnSQLTableCreated, "CREATE TABLE IF NOT EXISTS `spraymanager` (`steamid` VARCHAR(32) NOT NULL, `name` VARCHAR(32) NOT NULL, `unbantime` INT, `issuersteamid` VARCHAR(32), `issuername` VARCHAR(32) NOT NULL, `issuedtime` INT, `issuedreason` VARCHAR(64) NOT NULL, PRIMARY KEY(steamid)) CHARACTER SET utf8 COLLATE utf8_general_ci;");
		}

		return;
	}

	g_bGotBans = true;

	if (g_bGotBlacklist)
	{
		if (g_bLoadedLate)
		{
			if (CreateTimer(2.5, RetryUpdatingPlayerInfo) == null)
			{
				LogError("Failed to create player info updater timer, attempting to update info now.");

				for (int i = 1; i <= MaxClients; i++)
				{
					if (!IsValidClient)
						continue;

					OnClientPostAdminCheck(i);
				}
			}
		}

		LogMessage("Successfully connected to %s database!", g_bSQLite ? "SQLite" : "mySQL");

		g_bFullyConnected = true;
	}
}

public Action RetryMainTableCreation(Handle hTimer)
{
	if (g_bSQLite)
		SQL_TQuery(g_hDatabase, OnSQLTableCreated, "CREATE TABLE IF NOT EXISTS `spraymanager` (`steamid` TEXT NOT NULL, `name` TEXT DEFAULT 'unknown', `unbantime` INTEGER, `issuersteamid` TEXT, `issuername` TEXT DEFAULT 'unknown', `issuedtime` INTEGER NOT NULL, `issuedreason` TEXT DEFAULT 'none', PRIMARY KEY(steamid));");
	else
		SQL_TQuery(g_hDatabase, OnSQLTableCreated, "CREATE TABLE IF NOT EXISTS `spraymanager` (`steamid` VARCHAR(32) NOT NULL, `name` VARCHAR(32) NOT NULL, `unbantime` INT, `issuersteamid` VARCHAR(32), `issuername` VARCHAR(32) NOT NULL, `issuedtime` INT, `issuedreason` VARCHAR(64) NOT NULL, PRIMARY KEY(steamid)) CHARACTER SET utf8 COLLATE utf8_general_ci;");
}

public void OnSQLSprayBlacklistCreated(Handle hParent, Handle hChild, const char[] err, any data)
{
	if (hChild == null)
	{
		LogError("Database error while creating/checking for \"sprayblacklist\" table, retrying in 10 seconds. (%s)", err);

		if (CreateTimer(10.0, RetryBlacklistTableCreation) == null)
		{
			LogError("Failed to create re-query timer, trying to query now.");

			if (g_bSQLite)
				SQL_TQuery(g_hDatabase, OnSQLSprayBlacklistCreated, "CREATE TABLE IF NOT EXISTS `sprayblacklist` (`sprayhash` TEXT NOT NULL, `sprayer` TEXT DEFAULT 'unknown', `sprayersteamid` TEXT NOT NULL, PRIMARY KEY(sprayhash));");
			else
				SQL_TQuery(g_hDatabase, OnSQLSprayBlacklistCreated, "CREATE TABLE IF NOT EXISTS `sprayblacklist` (`sprayhash` VARCHAR(16) NOT NULL, `sprayer` VARCHAR(32) NOT NULL, `sprayersteamid` VARCHAR(32) NOT NULL, PRIMARY KEY(sprayhash)) CHARACTER SET utf8 COLLATE utf8_general_ci;");
		}

		return;
	}

	g_bGotBlacklist = true;

	if (g_bGotBans)
	{
		if (g_bLoadedLate)
		{
			if (CreateTimer(2.5, RetryUpdatingPlayerInfo) == null)
			{
				LogError("Failed to create player info updater timer, attempting to update info now.");

				for (int i = 1; i <= MaxClients; i++)
				{
					if (!IsValidClient)
						continue;

					OnClientPostAdminCheck(i);
				}
			}
		}

		LogMessage("Successfully connected to %s database!", g_bSQLite ? "SQLite" : "mySQL");

		g_bFullyConnected = true;
	}
}

public Action RetryBlacklistTableCreation(Handle hTimer)
{
	if (g_bSQLite)
		SQL_TQuery(g_hDatabase, OnSQLSprayBlacklistCreated, "CREATE TABLE IF NOT EXISTS `sprayblacklist` (`sprayhash` TEXT NOT NULL, `sprayer` TEXT DEFAULT 'unknown', `sprayersteamid` TEXT NOT NULL, PRIMARY KEY(sprayhash));");
	else
		SQL_TQuery(g_hDatabase, OnSQLSprayBlacklistCreated, "CREATE TABLE IF NOT EXISTS `sprayblacklist` (`sprayhash` VARCHAR(16) NOT NULL, `sprayer` VARCHAR(32) NOT NULL, `sprayersteamid` VARCHAR(32) NOT NULL, PRIMARY KEY(sprayhash)) CHARACTER SET utf8 COLLATE utf8_general_ci;");
}

public Action RetryUpdatingPlayerInfo(Handle hTimer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient)
			continue;

		OnClientPostAdminCheck(i);
	}
}

public void CVarHook_DecalFrequency(ConVar cvar, const char[] sOldValue, const char[] sNewValue)
{
	if (cvar == g_cvarHookedDecalFrequency)
	{
		if (StringToInt(sNewValue) != 0)
		{
			LogMessage("ConVar \"decalfrequency\" needs to be 0 at all times, please use sm_decalfrequency instead.");
			cvar.IntValue = 0;
		}
	}
}

bool SprayBanClient(int client, int target, int iBanLength, const char[] sReason)
{
	if (!IsValidClient(target))
	{
		ReplyToCommand(client, "[SprayManager] Target is no longer valid.");
		return false;
	}

	if (g_hDatabase == null || !g_bFullyConnected)
	{
		ReplyToCommand(client, "[SprayManager] Database is not connected.");
		return false;
	}

	if (g_bSprayBanned[target])
	{
		ReplyToCommand(client, "[SprayManager] %N is already spray banned.", target);
		return false;
	}

	char sQuery[512];
	char sAdminName[64];
	char sTargetName[64];
	char sTargetSteamID[32];
	char sAdminSteamID[32];

	Format(sAdminName, sizeof(sAdminName), "%N", client);
	GetClientName(target, sTargetName, sizeof(sTargetName));

	if (client)
		GetClientAuthId(client, AuthId_Steam2, sAdminSteamID, sizeof(sAdminSteamID));
	else
		strcopy(sAdminSteamID, sizeof(sAdminSteamID), "STEAM_ID_SERVER");

	GetClientAuthId(target, AuthId_Steam2, sTargetSteamID, sizeof(sTargetSteamID));

	char[] sSafeAdminName = new char[2 * strlen(sAdminName) + 1];
	char[] sSafeTargetName = new char[2 * strlen(sTargetName) + 1];
	char[] sSafeReason = new char[2 * strlen(sReason) + 1];
	SQL_EscapeString(g_hDatabase, sAdminName, sSafeAdminName, 2 * strlen(sAdminName) + 1);
	SQL_EscapeString(g_hDatabase, sTargetName, sSafeTargetName, 2 * strlen(sTargetName) + 1);
	SQL_EscapeString(g_hDatabase, sReason, sSafeReason, 2 * strlen(sReason) + 1);

	Format(sQuery, sizeof(sQuery), "INSERT INTO `spraymanager` (`steamid`, `name`, `unbantime`, `issuersteamid`, `issuername`, `issuedtime`, `issuedreason`) VALUES ('%s', '%s', '%i', '%s', '%s', '%i', '%s');",
		sTargetSteamID, sSafeTargetName, iBanLength ? (GetTime() + (iBanLength * 60)) : 0, sAdminSteamID, sSafeAdminName, GetTime(), strlen(sSafeReason) > 1 ? sSafeReason : "none");

	SQL_TQuery(g_hDatabase, DummyCallback, sQuery);

	strcopy(g_sBanIssuer[target], sizeof(g_sBanIssuer[]), sAdminName);
	strcopy(g_sBanIssuerSID[target], sizeof(g_sBanIssuerSID[]), sAdminSteamID);
	strcopy(g_sBanReason[target], sizeof(g_sBanReason[]), strlen(sReason) ? sReason : "none");
	g_bSprayBanned[target] = true;
	g_iSprayBanTimestamp[target] = GetTime();
	g_iSprayUnbanTimestamp[target] = iBanLength ? (GetTime() + (iBanLength * 60)) : 0;
	g_fNextSprayTime[target] = 0.0;

	g_bAllowSpray = true;
	SprayClientDecal(target, 0, ACTUAL_NULL_VECTOR);

	return true;
}

bool SprayUnbanClient(int client)
{
	if (!IsValidClient(client))
		return false;

	if (g_hDatabase == null || !g_bFullyConnected)
		return false;

	if (!g_bSprayBanned[client])
		return false;

	char sQuery[128];
	char sClientSteamID[32];

	GetClientAuthId(client, AuthId_Steam2, sClientSteamID, sizeof(sClientSteamID));
	Format(sQuery, sizeof(sQuery), "DELETE FROM `spraymanager` WHERE steamid = '%s';", sClientSteamID);

	SQL_TQuery(g_hDatabase, DummyCallback, sQuery);

	strcopy(g_sBanIssuer[client], sizeof(g_sBanIssuer[]), "");
	strcopy(g_sBanIssuerSID[client], sizeof(g_sBanIssuerSID[]), "");
	strcopy(g_sBanReason[client], sizeof(g_sBanReason[]), "");
	g_bSprayBanned[client] = false;
	g_iSprayLifetime[client] = 0;
	g_iSprayBanTimestamp[client] = 0;
	g_iSprayUnbanTimestamp[client] = -1;
	g_fNextSprayTime[client] = 0.0;

	return true;
}

bool BanClientSpray(int client)
{
	if (!IsValidClient(client))
		return false;

	if (g_hDatabase == null || !g_bFullyConnected)
		return false;

	if (g_bSprayHashBanned[client])
		return false;

	char sQuery[256];
	char sTargetName[64];
	char sTargetSteamID[32];

	GetClientName(client, sTargetName, sizeof(sTargetName));
	GetClientAuthId(client, AuthId_Steam2, sTargetSteamID, sizeof(sTargetSteamID));

	char[] sSafeTargetName = new char[2 * strlen(sTargetName) + 1];
	SQL_EscapeString(g_hDatabase, sTargetName, sSafeTargetName, 2 * strlen(sTargetName) + 1);

	Format(sQuery, sizeof(sQuery), "INSERT INTO `sprayblacklist` (`sprayhash`, `sprayer`, `sprayersteamid`) VALUES ('%s', '%s', '%s');",
		g_sSprayHash[client], sSafeTargetName, sTargetSteamID);

	SQL_TQuery(g_hDatabase, DummyCallback, sQuery);

	g_bSprayHashBanned[client] = true;

	g_bAllowSpray = true;
	SprayClientDecal(client, 0, ACTUAL_NULL_VECTOR);

	return true;
}

bool UnbanClientSpray(int client)
{
	if (!IsValidClient(client))
		return false;

	if (g_hDatabase == null || !g_bFullyConnected)
		return false;

	if (!g_bSprayHashBanned[client])
		return false;

	char sQuery[128];
	Format(sQuery, sizeof(sQuery), "DELETE FROM `sprayblacklist` WHERE `sprayhash` = '%s';", g_sSprayHash[client]);

	SQL_TQuery(g_hDatabase, DummyCallback, sQuery);

	g_bSprayHashBanned[client] = false;

	return true;
}

void UpdatePlayerInfo(int client)
{
	if (!IsValidClient(client))
		return;

	if (g_hDatabase == null || !g_bFullyConnected)
		return;

	char sSteamID[32];
	char sQuery[128];

	GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID));
	Format(sQuery, sizeof(sQuery), "SELECT * FROM `spraymanager` WHERE `steamid` = '%s';", sSteamID);

	SQL_TQuery(g_hDatabase, OnSQLCheckBanQuery, sQuery, client, DBPrio_High);
}

void UpdateSprayHashInfo(int client)
{
	if (!IsValidClient(client))
		return;

	if (g_hDatabase == null || !g_bFullyConnected)
		return;

	char sSprayQuery[128];

	GetPlayerDecalFile(client, g_sSprayHash[client], sizeof(g_sSprayHash[]));
	Format(sSprayQuery, sizeof(sSprayQuery), "SELECT * FROM `sprayblacklist` WHERE `sprayhash` = '%s';", g_sSprayHash[client]);

	SQL_TQuery(g_hDatabase, OnSQLCheckSprayHashBanQuery, sSprayQuery, client, DBPrio_High);
}

public void DummyCallback(Handle hOwner, Handle hChild, const char[] err, any data)
{
	if (hOwner == null || hChild == null)
		LogError("Query error. (%s)", err);
}

public void OnSQLCheckBanQuery(Handle hParent, Handle hChild, const char[] err, any client)
{
	if (!IsValidClient(client))
		return;

	if (hChild == null)
	{
		LogError("An error occurred while querying the database for a user ban, retrying in 10 seconds. (%s)", err);

		if (CreateTimer(10.0, RetryPlayerInfoUpdate, client) == null)
		{
			LogError("Failed to create query timer, trying to query now.");
			UpdatePlayerInfo(client);
		}

		return;
	}

	if (SQL_FetchRow(hChild))
	{
		g_bSprayBanned[client] = true;
		g_iSprayUnbanTimestamp[client] = SQL_FetchInt(hChild, 2);
		g_iSprayBanTimestamp[client] = SQL_FetchInt(hChild, 5);

		SQL_FetchString(hChild, 3, g_sBanIssuerSID[client], sizeof(g_sBanIssuerSID[]));
		SQL_FetchString(hChild, 4, g_sBanIssuer[client], sizeof(g_sBanIssuer[]));
		SQL_FetchString(hChild, 6, g_sBanReason[client], sizeof(g_sBanReason[]));
	}
}

public void OnSQLCheckSprayHashBanQuery(Handle hParent, Handle hChild, const char[] err, any client)
{
	if (!IsValidClient(client))
		return;

	if (hChild == null)
	{
		LogError("An error occurred while querying the database for a spray ban, retrying in 10 seconds. (%s)", err);

		if (CreateTimer(10.0, RetrySprayHashUpdate, client) == null)
		{
			LogError("Failed to create spray query timer, trying to query now.");
			UpdateSprayHashInfo(client);
		}

		return;
	}

	if (SQL_FetchRow(hChild))
		g_bSprayHashBanned[client] = true;
}

public Action RetryPlayerInfoUpdate(Handle hTimer, any client)
{
	UpdatePlayerInfo(client);
}

public Action RetrySprayHashUpdate(Handle hTimer, any client)
{
	UpdateSprayHashInfo(client);
}

bool ForceSpray(int client, int target, bool bPlaySound=true)
{
	if (!IsValidClient(target))
		return false;

	float vecEndPos[3];

	if (TracePlayerAngles(client, vecEndPos))
	{
		SprayClientDecal(target, 0, vecEndPos);

		if (bPlaySound)
			EmitSoundToAll("player/sprayer.wav", SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, _, _, _, vecEndPos);

		return true;
	}

	PrintToChat(client, "\x01\x04[SprayManager]\x01 Could not spray here, try somewhere else.");

	return false;
}

bool SprayClientDecal(int client, int iEntity, float vecOrigin[3])
{
	if (!IsValidClient(client))
		return false;

	TE_Start("Player Decal");
	TE_WriteVector("m_vecOrigin", vecOrigin);
	TE_WriteNum("m_nEntity", iEntity);
	TE_WriteNum("m_nPlayer", client);
	TE_SendToAll();

	return true;
}

bool TracePlayerAngles(int client, float vecResult[3])
{
	if (!IsValidClient(client))
		return false;

	float vecEyeAngles[3];
	float vecEyeOrigin[3];

	GetClientEyeAngles(client, vecEyeAngles);
	GetClientEyePosition(client, vecEyeOrigin);

	Handle hTraceRay = TR_TraceRayFilterEx(vecEyeOrigin, vecEyeAngles, MASK_SHOT_HULL, RayType_Infinite, TraceFilterEntities);

	if (TR_DidHit(hTraceRay))
	{
		TR_GetEndPosition(vecResult, hTraceRay);
		CloseHandle(hTraceRay);

		return true;
	}

	CloseHandle(hTraceRay);

	return false;
}

bool TracePlayerAnglesRanged(int client, float fMaxDistance)
{
	if (!IsValidClient(client))
		return false;

	float vecEyeAngles[3];
	float vecEyeOrigin[3];
	float vecDirection[3];
	float vecEndPos[3];

	GetClientEyeAngles(client, vecEyeAngles);
	GetClientEyePosition(client, vecEyeOrigin);
	GetAngleVectors(vecEyeAngles, vecDirection, NULL_VECTOR, NULL_VECTOR);

	vecEndPos[0] = vecEyeOrigin[0] + (vecDirection[0] * fMaxDistance);
	vecEndPos[1] = vecEyeOrigin[1] + (vecDirection[1] * fMaxDistance);
	vecEndPos[2] = vecEyeOrigin[2] + (vecDirection[2] * fMaxDistance);

	Handle hTraceRay = TR_TraceRayFilterEx(vecEyeOrigin, vecEndPos, MASK_SHOT_HULL, RayType_EndPoint, TraceFilterEntities);

	if (TR_DidHit(hTraceRay))
	{
		CloseHandle(hTraceRay);

		return true;
	}

	return false;
}

void ClearPlayerInfo(int client)
{
	if (!IsValidClient(client))
		return;

	strcopy(g_sBanIssuer[client], sizeof(g_sBanIssuer[]), "");
	strcopy(g_sBanIssuerSID[client], sizeof(g_sBanIssuerSID[]), "");
	strcopy(g_sBanReason[client], sizeof(g_sBanReason[]), "");
	strcopy(g_sSprayHash[client], sizeof(g_sSprayHash[]), "");
	g_bSprayBanned[client] = false;
	g_bSprayHashBanned[client] = false;
	g_iSprayLifetime[client] = 0;
	g_iSprayBanTimestamp[client] = 0;
	g_iSprayUnbanTimestamp[client] = -1;
	g_fNextSprayTime[client] = 0.0;
	g_vecSprayOrigin[client] = ACTUAL_NULL_VECTOR;
}

void FormatRemainingTime(int iTimestamp, char[] sBuffer, int iBuffSize)
{
	if (!iTimestamp)
	{
		Format(sBuffer, iBuffSize, "Permanent");
		return;
	}

	int tstamp = (iTimestamp - GetTime());

	int days = (tstamp / 86400);
	int hours = ((tstamp / 3600) % 24);
	int minutes = ((tstamp / 60) % 60);
	int seconds = (tstamp % 60);

	if (tstamp > 86400)
	{
		Format(sBuffer, iBuffSize, "%d %s, %d %s, %d %s, %d %s", days, SingularOrMultiple(days) ? "Days" : "Day",
			hours, SingularOrMultiple(hours) ? "Hours" : "Hour", minutes, SingularOrMultiple(minutes) ? "Minutes" : "Minute",
			seconds, SingularOrMultiple(seconds)?"Seconds":"Second");
	}
	else if (tstamp > 3600)
	{
		Format(sBuffer, iBuffSize, "%d %s, %d %s, %d %s", hours, SingularOrMultiple(hours) ? "Hours" : "Hour",
			minutes, SingularOrMultiple(minutes) ? "Minutes" : "Minute", seconds, SingularOrMultiple(seconds) ? "Seconds" : "Second");
	}
	else if (tstamp > 60)
	{
		Format(sBuffer, iBuffSize, "%d %s, %d %s", minutes, SingularOrMultiple(minutes) ? "Minutes" : "Minute",
			seconds, SingularOrMultiple(seconds) ? "Seconds" : "Second");
	}
	else
		Format(sBuffer, iBuffSize, "%d %s", seconds, SingularOrMultiple(seconds) ? "Seconds":"Second");
}

bool IsPointInsideAABB(float vecPoint[3], float AABB[6])
{
	if (vecPoint[0] >= AABB[AABBMinX] && vecPoint[0] <= AABB[AABBMaxX] &&
		vecPoint[1] >= AABB[AABBMinY] && vecPoint[1] <= AABB[AABBMaxY] &&
		vecPoint[2] >= AABB[AABBMinZ] && vecPoint[2] <= AABB[AABBMaxZ])
	{
		return true;
	}

	return false;
}

bool CheckForAABBCollision(float AABB1[6], float AABB2[6])
{
	if (AABB1[AABBMinX] > AABB2[AABBMaxX]) return false;
	if (AABB1[AABBMinY] > AABB2[AABBMaxY]) return false;
	if (AABB1[AABBMinZ] > AABB2[AABBMaxZ]) return false;
	if (AABB1[AABBMaxX] < AABB2[AABBMinX]) return false;
	if (AABB1[AABBMaxY] < AABB2[AABBMinY]) return false;
	if (AABB1[AABBMaxZ] < AABB2[AABBMinZ]) return false;

	return true;
}

stock bool IsVectorZero(float vecPos[3])
{
	return ((vecPos[0] == 0.0) && (vecPos[1] == 0.0) && (vecPos[2] == 0.0));
}

stock bool SingularOrMultiple(int num)
{
	if (!num || num > 1)
		return true;

	return false;
}

stock bool TraceFilterEntities(int entity, int contentsMask)
{
	return false;
}

stock bool IsValidClient(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
		return false;

	return IsClientAuthorized(client);
}
