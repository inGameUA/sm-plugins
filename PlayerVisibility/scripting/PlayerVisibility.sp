#include <sourcemod>
#include <sdkhooks>
#include <zombiereloaded>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name 			= "PlayerVisibility",
	author 			= "BotoX",
	description 	= "Fades players away when you get close to them.",
	version 		= "1.1",
	url 			= ""
};

ConVar g_CVar_MaxDistance;
ConVar g_CVar_MinFactor;
ConVar g_CVar_MinAlpha;

float g_fMaxDistance;
float g_fMinFactor;
float g_fMinAlpha;

int g_Client_Alpha[MAXPLAYERS + 1] = {255, ...};

public void OnPluginStart()
{
	g_CVar_MaxDistance = CreateConVar("sm_pvis_maxdistance", "100.0", "Distance at which models stop fading.", 0, true, 0.0);
	g_fMaxDistance = g_CVar_MaxDistance.FloatValue;
	g_CVar_MaxDistance.AddChangeHook(OnConVarChanged);

	g_CVar_MinFactor = CreateConVar("sm_pvis_minfactor", "0.75", "Smallest allowed alpha factor per client.", 0, true, 0.0, true, 1.0);
	g_fMinFactor = g_CVar_MinFactor.FloatValue;
	g_CVar_MinFactor.AddChangeHook(OnConVarChanged);

	g_CVar_MinAlpha = CreateConVar("sm_pvis_minalpha", "75.0", "Minimum allowed alpha value.", 0, true, 0.0, true, 255.0);
	g_fMinAlpha = g_CVar_MinAlpha.FloatValue;
	g_CVar_MinAlpha.AddChangeHook(OnConVarChanged);

	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client))
			OnClientPutInServer(client);
	}

	AutoExecConfig(true, "plugin.PlayerVisibility");
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(convar == g_CVar_MaxDistance)
		g_fMaxDistance = g_CVar_MaxDistance.FloatValue;

	else if(convar == g_CVar_MinFactor)
		g_fMinFactor = g_CVar_MinFactor.FloatValue;

	else if(convar == g_CVar_MinAlpha)
		g_fMinAlpha = g_CVar_MinAlpha.FloatValue;
}

public void OnPluginEnd()
{
	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client))
		{
			if(g_Client_Alpha[client] != 255.0)
				SetEntityRenderMode(client, RENDER_NORMAL);

			OnClientDisconnect(client);
		}
	}
}

public void OnClientPutInServer(int client)
{
	g_Client_Alpha[client] = 255;
	SDKHook(client, SDKHook_PostThinkPost, OnPostThinkPost);
}

public void OnClientDisconnect(int client)
{
	g_Client_Alpha[client] = 255;
	SDKUnhook(client, SDKHook_PostThinkPost, OnPostThinkPost);
}

public void OnPostThinkPost(int client)
{
	if(!IsPlayerAlive(client))
	{
		if(g_Client_Alpha[client] != 255)
		{
			g_Client_Alpha[client] = 255;
			ToolsSetEntityAlpha(client, 255);
		}
		return;
	}

	if(GetEntityRenderMode(client) == RENDER_NONE)
	{
		g_Client_Alpha[client] = 0;
		return;
	}

	int aColor[4];
	ToolsGetEntityColor(client, aColor);
	if(!aColor[3])
	{
		g_Client_Alpha[client] = 0;
		return;
	}

	if(!ZR_IsClientHuman(client))
	{
		if(g_Client_Alpha[client] != 255)
		{
			g_Client_Alpha[client] = 255;
			ToolsSetEntityAlpha(client, 255);
		}
		return;
	}

	float fAlpha = 255.0;
	for(int i = 1; i <= MaxClients; i++)
	{
		if(i == client || !IsClientInGame(i) || !IsPlayerAlive(i))
			continue;

		if(!ZR_IsClientHuman(i))
			continue;

		static float fVec1[3];
		static float fVec2[3];
		GetClientAbsOrigin(client, fVec1);
		GetClientAbsOrigin(i, fVec2);

		float fDistance = GetVectorDistance(fVec1, fVec2, false);
		if(fDistance <= g_fMaxDistance)
		{
			float fFactor = fDistance / g_fMaxDistance;
			if(fFactor < g_fMinFactor)
				fFactor = g_fMinFactor;

			fAlpha *= fFactor;
		}
	}

	if(fAlpha < g_fMinAlpha)
		fAlpha = g_fMinAlpha;

	int Alpha = RoundToNearest(fAlpha);
	int LastAlpha = g_Client_Alpha[client];
	g_Client_Alpha[client] = Alpha;

	if(Alpha == LastAlpha)
		return;

	ToolsSetEntityAlpha(client, Alpha);
}

stock void ToolsSetEntityAlpha(int client, int Alpha)
{
	if(Alpha == 255)
	{
		SetEntityRenderMode(client, RENDER_NORMAL);
		return;
	}

	int aColor[4];
	ToolsGetEntityColor(client, aColor);

	SetEntityRenderMode(client, RENDER_TRANSCOLOR);
	SetEntityRenderColor(client, aColor[0], aColor[1], aColor[2], Alpha);
}

stock void ToolsGetEntityColor(int entity, int aColor[4])
{
	static bool s_GotConfig = false;
	static char s_sProp[32];

	if(!s_GotConfig)
	{
		Handle GameConf = LoadGameConfigFile("core.games");
		bool Exists = GameConfGetKeyValue(GameConf, "m_clrRender", s_sProp, sizeof(s_sProp));
		CloseHandle(GameConf);

		if(!Exists)
			strcopy(s_sProp, sizeof(s_sProp), "m_clrRender");

		s_GotConfig = true;
	}

	int Offset = GetEntSendPropOffs(entity, s_sProp);

	for(int i = 0; i < 4; i++)
		aColor[i] = GetEntData(entity, Offset + i, 1);
}
