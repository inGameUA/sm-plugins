#if defined _AfkManager_Included
	#endinput
#endif
#define _AfkManager_Included

native int GetClientIdleTime(int client);

public SharedPlugin __pl_AfkManager =
{
	name = "AfkManager",
	file = "AfkManager.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_AfkManager_SetNTVOptional()
{
	MarkNativeAsOptional("GetClientIdleTime");
}
#endif
