#pragma semicolon 1

#include <sourcemod>

#define INFECTED_TEAM 3
#define ZC_HUNTER 3
#define MIN_LUNGE_ANGLE 15.0
#define MAX_LUNGE_ANGLE 35.0
#define STRAIGHT_POUNCE_PROXIMITY 100

public Plugin:myinfo = {
	name = "AI: Hunter Pouncing",
	author = "Breezy, High Cookie, Standalone",
	description = "Modifies AI hunter lunge patterns",
	version = "1.0"
};

// Vanilla Cvars
new Handle:hCvarHunterCommittedAttackRange;
new Handle:hCvarHunterPounceReadyRange;
new Handle:hCvarHunterLeapAwayGiveUpRange; 
new Handle:hCvarHunterPounceMaxLoftAngle; 
new Handle:hCvarLungeInterval; 

new Handle:hCvarFastPounceProximity; // Distance at which hunter begins pouncing fast
new g_iFastPounceProximity;

new bool:bHasQueuedLunge[MAXPLAYERS];
new bool:bCanLunge[MAXPLAYERS];
new bool:bHasBeenShoved[MAXPLAYERS];

public OnPluginStart() {
	// CONSOLE VARIABLES:	
	
	// range at which hunter is committed to attack
	hCvarHunterCommittedAttackRange = FindConVar("hunter_committed_attack_range");
	SetCheatConVarInt(hCvarHunterCommittedAttackRange, 10000);
	
	// range at which hunter prepares pounce
	hCvarHunterPounceReadyRange = FindConVar("hunter_pounce_ready_range");
	SetCheatConVarInt(hCvarHunterPounceReadyRange, 500);
	
	// range at which shooting a non-committed hunter will cause it to leap away
	hCvarHunterLeapAwayGiveUpRange = FindConVar("hunter_leap_away_give_up_range");
	SetCheatConVarInt(hCvarHunterLeapAwayGiveUpRange, 0); 
	
	// cooldown on lunges
	hCvarLungeInterval = FindConVar("z_lunge_interval");
	
	// maximum loft angle hunters can pounce
	hCvarHunterPounceMaxLoftAngle = FindConVar("hunter_pounce_max_loft_angle");
	SetCheatConVarInt(hCvarHunterPounceMaxLoftAngle, 0);
	
	// proximity to nearest survivor when plugin starts to force hunters to lunge ASAP
	hCvarFastPounceProximity = CreateConVar("ai_fast_pounce_proximity", "1000", "At what distance to start pouncing fast");
	HookConVarChange(hCvarFastPounceProximity, OnConVarChange);
	g_iFastPounceProximity = GetConVarInt(hCvarFastPounceProximity);
	
	// EVENT HOOKS:
	HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Pre); // Allow fast pouncing on newly spawned hunters
	HookEvent("ability_use", OnAbilityUse, EventHookMode_Pre); // Zig zag pouncing
}

// Initiating plugin for hunters as they spawn
public Action:OnPlayerSpawn(Handle:event, String:name[], bool:dontBroadcast) {
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (IsBotHunter(client)) {
		bHasQueuedLunge[client] = false;
		bCanLunge[client] = true;
		bHasBeenShoved[client] = false;
	}
}

// Update internally when a hooked cvar changes
public OnConVarChange(Handle:convar, const String:oldValue[], const String:newValue[]) {
	g_iFastPounceProximity = GetConVarInt(hCvarFastPounceProximity);
}

public OnPluginEnd() {
	ResetConVar(hCvarHunterCommittedAttackRange);
	ResetConVar(hCvarHunterPounceReadyRange);
	ResetConVar(hCvarHunterLeapAwayGiveUpRange);
	ResetConVar(hCvarHunterPounceMaxLoftAngle);
}

/***********************************************************************************************************************************************************************************

																	POUNCING AT AN ANGLE TO SURVIVORS

***********************************************************************************************************************************************************************************/

public Action:OnAbilityUse(Handle:event, String:name[], bool:dontBroadcast) {
	new String:abilityName[32];
	GetEventString(event, "ability", abilityName, sizeof(abilityName));
	// if a hunter is about to pounce
	if (StrEqual(abilityName, "ability_lunge")) { 
		// is it a bot
		new hunter = GetClientOfUserId(GetEventInt(event, "userid"));
		if (IsBotHunter(hunter)) {		
			bHasBeenShoved[hunter] = false;
			
			// Get the hunter's lunge entity
			new entLunge = GetEntPropEnt(hunter, Prop_Send, "m_customAbility");	
			
			// get the vector from the lunge entity
			new Float:lungeVector[3];
			GetEntPropVector(entLunge, Prop_Send, "m_queuedLunge", lungeVector);
			
			// if survivor is not too close, set a new vector that's angled slightly to the original
			if (GetSurvivorProximity(hunter) > STRAIGHT_POUNCE_PROXIMITY) {
				// Generate a random angle within the configured range
				new Float:randomAngle = GetRandomFloat(MIN_LUNGE_ANGLE, MAX_LUNGE_ANGLE); // angle in degrees
				
				// positive or negative direction (angle lunge leftwards/rightwards)
				new Float:angleSign;
				if (GetRandomInt(0, 1) == 0) {
					angleSign = 1.0;
				} else {
					angleSign = -1.0;
				}				
				AngleLunge(entLunge, FloatMul(randomAngle, angleSign));	
				
				return Plugin_Changed;
			}			
		}		
	}
	return Plugin_Continue;
}

// Lunge modification
AngleLunge(lungeEntity, Float:turnAngle) {
	// Get the original lunge's vector
	new Float:lungeVector[3];
	GetEntPropVector(lungeEntity, Prop_Send, "m_queuedLunge", lungeVector);
	new Float:x = lungeVector[0];
	new Float:y = lungeVector[1];
	new Float:z = lungeVector[2];
    
    // Create a new vector of the desired angle from the original
	turnAngle = DegToRad(turnAngle); // convert angle to radian form
	decl Float:forcedLunge[3];
	forcedLunge[0] = x * Cosine(turnAngle) - y * Sine(turnAngle);
	forcedLunge[1] = x * Sine(turnAngle)   + y * Cosine(turnAngle);
	forcedLunge[2] = z;
	
	SetEntPropVector(lungeEntity, Prop_Send, "m_queuedLunge", forcedLunge);
}

/***********************************************************************************************************************************************************************************

																		FAST POUNCING

***********************************************************************************************************************************************************************************/

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon) {
	//Proceed if this player is a hunter
	if(IsBotHunter(client)) {
		new hunter = client;		
		if (!bHasBeenShoved[hunter]) {
			new flags = GetEntityFlags(hunter);
			//Proceed if the hunter is in a position to pounce
			if( (flags & FL_DUCKING) && (flags & FL_ONGROUND) ) {				
				new iSurvivorsProximity = GetSurvivorProximity(hunter);
				new bool:bHasLOS = bool:GetEntProp(hunter, Prop_Send, "m_hasVisibleThreats"); // Line of sight to survivors
				
				// Start fast pouncing if close enough to survivors
				if (bHasLOS && (iSurvivorsProximity < g_iFastPounceProximity) ) {
					buttons &= ~IN_ATTACK; // release attack button; precautionary
					
					// Queue a pounce/lunge
					if (!bHasQueuedLunge[hunter]) { // check lunge interval timer has not already been initiated
						bCanLunge[hunter] = false;
						bHasQueuedLunge[hunter] = true; // block duplicate lunge interval timers
						CreateTimer(GetConVarFloat(hCvarLungeInterval), Timer_LungeInterval, any:hunter, TIMER_FLAG_NO_MAPCHANGE);
					} else if (bCanLunge[hunter]) { // end of lunge interval; lunge!
						buttons |= IN_ATTACK;
						bHasQueuedLunge[hunter] = false; // unblock lunge interval timer
					} // else lunge queue is being processed
				}				
			}
		}		
	}
	return Plugin_Changed;
}

// After the given interval, hunter is allowed to pounce/lunge
public Action:Timer_LungeInterval(Handle:timer, any:client) {
	bCanLunge[client] = true;
}

// Disable fast pouncing when shoved
public Action:OnPlayerShoved(Handle:event, String:name[], bool:dontBroadcast) {
	new shovedPlayer = GetClientOfUserId(GetEventInt(event, "userid"));
	if (IsBotHunter(shovedPlayer)) {
		bHasBeenShoved[shovedPlayer] = true;
	}
}

/***********************************************************************************************************************************************************************************

																				UTILITY
																	
***********************************************************************************************************************************************************************************/

bool:IsBotHunter(client) {
	// Check the input is valid
	if (!IsValidClient(client)) return false;
	// Check if player is on the infected team, a hunter, and a bot
	if (GetClientTeam(client) == INFECTED_TEAM) {
		new zombieClass = GetEntProp(client, Prop_Send, "m_zombieClass");
		if (zombieClass == ZC_HUNTER) {
			if(IsFakeClient(client)) {
				return true;
			}
		}
	}
	return false; // otherwise
}

GetSurvivorProximity(referenceClient) {
	// Get the reference's position
	new Float:referencePosition[3];
	GetEntPropVector(referenceClient, Prop_Send, "m_vecOrigin", referencePosition);
	// Find the proximity of the closest survivor
	new iClosestAbsDisplacement = -1; // closest absolute displacement
	for (new client = 1; client < MaxClients; client++) {
		if (IsValidClient(client) && IsSurvivor(client)) {
			// Get displacement between this survivor and the reference
			new Float:survivorPosition[3];
			GetEntPropVector(client, Prop_Send, "m_vecOrigin", survivorPosition);
			new iAbsDisplacement = RoundToNearest(GetVectorDistance(referencePosition, survivorPosition));
			// Start with the absolute displacement to the first survivor found:
			if (iClosestAbsDisplacement == -1) {
				iClosestAbsDisplacement = iAbsDisplacement;
			} else if (iAbsDisplacement < iClosestAbsDisplacement) { // closest survivor so far
				iClosestAbsDisplacement = iAbsDisplacement;
			}			
		}
	}
	// return the closest survivor's proximity
	return iClosestAbsDisplacement;
}

SetCheatConVarInt(Handle:hCvarHandle, value) {
	// unset cheat flag
	new cvarFlags = GetConVarFlags(hCvarHandle);
	SetConVarFlags(hCvarHandle, cvarFlags ^ FCVAR_CHEAT);
	// set new value
	SetConVarInt(hCvarHandle, value);
	// reset cheat flag
	SetConVarFlags(hCvarHandle, cvarFlags);
}

bool:IsValidClient(client) {
    if ( !( 1 <= client <= MaxClients ) || !IsClientInGame(client) ) return false;      
    return true; 
}

bool:IsSurvivor(client) {
	return (IsValidClient(client) && GetClientTeam(client) == 2);
}

/*
	Angle
	= 0.5 * Exp[ - (x - MEAN) ^ 2 / (2 * DEVIATION ^ 2) ] 
	+ 0.5 * Exp[ - (x + MEAN) ^ 2 / (2 * DEVIATION ^ 2) ]) / sqrt[ 2 * pi ] *15
	
	Suggested 
	- MEAN = 30
	- DEVIATION = 15
*/