#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <zombiereloaded>

public Plugin myinfo =
{
	name 			= "PlayerVisibility",
	author 			= "BotoX",
	description 	= "Fades players away when you get close to them.",
	version 		= "1.0",
	url 			= ""
};

int g_Client_Alpha[MAXPLAYERS + 1] = {255, ...};

public void OnPluginStart()
{
	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client))
			OnClientPutInServer(client);
	}
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
	SDKHook(client, SDKHook_PostThink, OnPostThink);
}

public void OnClientDisconnect(int client)
{
	SDKUnhook(client, SDKHook_PostThink, OnPostThink);
}

public void OnPostThink(client)
{
	if(!IsPlayerAlive(client))
		return;

	if(!ZR_IsClientHuman(client))
	{
		if(g_Client_Alpha[client] != 255)
		{
			g_Client_Alpha[client] = 255;
			if(GetEntityRenderMode(client) != RENDER_NONE)
				ToolsSetEntityAlpha(client, 255);
		}
		return;
	}

	if(GetEntityRenderMode(client) == RENDER_NONE)
	{
		g_Client_Alpha[client] = 255;
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

		float fMaxDistance = 150.0;
		float fDistance = GetVectorDistance(fVec1, fVec2, false);

		if(fDistance <= fMaxDistance)
		{
			float fFactor = fDistance / fMaxDistance;
			if(fFactor < 0.75)
				fFactor = 0.75;

			fAlpha *= fFactor;
		}
	}

	if(fAlpha < 100.0)
		fAlpha = 100.0;

	int Alpha = RoundToNearest(fAlpha);
	int LastAlpha = g_Client_Alpha[client];
	g_Client_Alpha[client] = Alpha;

	if(Alpha == LastAlpha)
		return;

	ToolsSetEntityAlpha(client, Alpha);
}

void ToolsSetEntityAlpha(int client, int Alpha)
{
	if(Alpha == 255)
	{
		SetEntityRenderMode(client, RENDER_NORMAL);
		return;
	}

	int aColor[4];
	ToolsGetEntityColor(client, aColor);

	SetEntityRenderMode(client, RENDER_TRANSCOLOR);
	SetEntityRenderColor(client, aColor[0], aColor[1], aColor[2], g_Client_Alpha[client]);
}

stock ToolsGetEntityColor(int entity, int aColor[4])
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
