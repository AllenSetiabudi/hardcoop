#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <colors>

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
#define POUNCE_DMG 24
#define DEFAULT_HUNTER_CLAW_DMG_AMOUNT 10
#define INTENDED_HUNTER_CLAW_DMG_AMOUNT 1
#define ZC_HUNTER 3

new const String:SI_Names[][] =
{
	"Unknown",
	"Smoker",
	"Boomer",
	"Hunter",
	"Spitter",
	"Jockey",
	"Charger",
	"Witch",
	"Tank",
	"Not SI"
};

new Handle:hCvarDmgThreshold;

public Plugin:myinfo =
{
	name = "Solo Mode Bot Slayer",
	author = "Wombat",
	description = "Slays infected when they cap you like in 1v1s",
	version = "0.1",
	url = ""
};

public OnPluginStart()
{
  new String:strDmg[16];
  IntToString(POUNCE_DMG, strDmg, sizeof(strDmg));
  hCvarDmgThreshold = CreateConVar("sm_1v1_dmgthreshold", strDmg, "Amount of damage done (at once) before SI suicides.", FCVAR_PLUGIN, true, 1.0);

  HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);

  for (new i = 1; i < MaxClients+1; i++) {
      if (IsClientInGame(i)) {
          SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
      }
  }
}

public OnClientPostAdminCheck(client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action:OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3])
{
  //PrintToChatAll("victim is %N, attacker is %N, inflictor is %N, damage is : %i, damage type is %i", victim, attacker, inflictor, Float:damage, damagetype);
  //PrintToChatAll("attacker class is %i, damage type is %i, weapon is %i, damage is %i, 24 float is %d", GetZombieClass(attacker), damagetype, weapon, damage, float());
  // If attacker is a hunter, and it was slash damage (therefore claw attack)
  if (GetZombieClass(attacker) == 3 && damage == float(DEFAULT_HUNTER_CLAW_DMG_AMOUNT))
  {
    //PrintToChatAll("setting damage to intended amount: %d", INTENDED_HUNTER_CLAW_DMG_AMOUNT);
    damage = float(INTENDED_HUNTER_CLAW_DMG_AMOUNT);
    return Plugin_Changed;
  }
  return Plugin_Continue;
}

public Action:Event_PlayerHurt(Handle:event, const String:name[], bool:dontBroadcast)
{
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));

	new damage = GetEventInt(event, "dmg_health");
	new zombie_class = GetZombieClass(attacker);

	//if (GetClientTeam(attacker) == TEAM_INFECTED) CPrintToChatAll("{green}%s{default} did {olive}%i{default} damage to {green}%N{default}. Threshold is {olive}%i", SI_Names[zombie_class], damage, victim, GetConVarInt(hCvarDmgThreshold));
	//PrintToChatAll("attacker is %N and team of attacker is %i", attacker, GetClientTeam(attacker));

	if (GetClientTeam(attacker) == TEAM_INFECTED && GetClientTeam(victim) == TEAM_SURVIVOR && zombie_class != 8 && damage >= GetConVarInt(hCvarDmgThreshold))
	{
    new remaining_health = GetClientHealth(attacker);
    CPrintToChatAll("{green}%s{default} had {olive}%d{default} health remaining!", SI_Names[zombie_class], remaining_health);

    // make slay all hunters
    //ForcePlayerSuicide(attacker);
    for (new i = 1; i <= GetMaxClients(); i++ )
    {
      if (IsClientInGame(i))
      {
        //PrintToChatAll("client number %i is %N, who is a %i on team %i", i, i, GetZombieClass(i), GetClientTeam(i));
        if (GetClientTeam(i) == TEAM_INFECTED && GetZombieClass(i) != 8)
        {
          ForcePlayerSuicide(i);
        }
      }
    }

    // freeze tank while ghost
    // fix show limits
    //rename
    //remove prints
	}
}

stock GetZombieClass(client) return GetEntProp(client, Prop_Send, "m_zombieClass");
