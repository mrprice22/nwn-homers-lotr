// csp_db.nss - persistence for the caster spell picker (roadmap:
// legendary-caster-spells-on-level-up).
//
// Campaign SQLite DB "cspelldb", keyed on GetObjectUUID() - shaped like
// legfeatdb / bestiarydb / meritdb.
//
// TWO TABLES, AND THE FIRST ONE IS THE WHOLE ANTI-FARM DESIGN.
//
//   csp_alloc(pid, class, paid_to, granted)
//       paid_to is a HIGH-WATER MARK: the class level through which this
//       character has already been paid its per-level spell picks. It is only
//       ever raised, never lowered. Everything that makes this feature safe
//       falls out of that one property:
//
//         * The retroactive make-good needs no separate mechanism. A character
//           that has never been seen has no row, so paid_to seeds at the cap
//           level (40) and the first check pays every level from 41 to where
//           the character actually is - 26 picks for a wizard 53. See
//           CSP_EnsureAllotment in csp_inc.nss.
//         * It pays exactly ONCE. After that first check paid_to is 53, so the
//           next check (login, rest, another level) owes nothing.
//         * It cannot be farmed by de-levelling and re-levelling. Dropping to
//           45 and climbing back to 53 leaves paid_to at 53 throughout, so the
//           climb pays nothing. This is the reason the row does not simply
//           store "levels above 40 times 2" and recompute.
//
//   csp_learn(pid, class, spell)
//       One row per spell this system granted. SPENT IS COUNT(*) OF THIS
//       TABLE, not a counter, so a double-clicked button cannot burn two picks
//       on one spell (the PK makes the second insert a no-op) and the ledger
//       can be audited spell by spell. Spells learned any other way - chargen,
//       levels 1-40, scribed from a scroll - are deliberately NOT in here:
//       this table is the record of what WE handed out, nothing else.
//
// The spells themselves live in the .bic like any other known spell; this DB
// only tracks the entitlement, which the .bic has nowhere to keep.

const string CSP_DB = "cspelldb";

void CSP_InitDb();
int  CSP_GetPaidTo(object oPC, int nClass, int nDefault);
int  CSP_GetGranted(object oPC, int nClass);
void CSP_SetAlloc(object oPC, int nClass, int nPaidTo, int nGranted);
int  CSP_GetSpent(object oPC, int nClass);
void CSP_RecordLearn(object oPC, int nClass, int nSpellId);
int  CSP_HasLearn(object oPC, int nClass, int nSpellId);

// Idempotent - safe to call on every login, level and window open.
void CSP_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(CSP_DB,
        "CREATE TABLE IF NOT EXISTS csp_alloc (" +
        "pid TEXT NOT NULL, class INTEGER NOT NULL," +
        "paid_to INTEGER NOT NULL, granted INTEGER NOT NULL," +
        "cdkey TEXT, updated_at TEXT DEFAULT CURRENT_TIMESTAMP," +
        "PRIMARY KEY(pid, class))");
    SqlStep(q);

    q = SqlPrepareQueryCampaign(CSP_DB,
        "CREATE TABLE IF NOT EXISTS csp_learn (" +
        "pid TEXT NOT NULL, class INTEGER NOT NULL, spell INTEGER NOT NULL," +
        "cdkey TEXT, learned_at TEXT DEFAULT CURRENT_TIMESTAMP," +
        "PRIMARY KEY(pid, class, spell))");
    SqlStep(q);
}

// The class level this character has already been paid through. nDefault is
// returned when there is no row at all - the caller passes the cap level, which
// is what makes a never-seen character's first check pay for every level it
// gained past the cap while the client was eating the picks.
int CSP_GetPaidTo(object oPC, int nClass, int nDefault)
{
    sqlquery q = SqlPrepareQueryCampaign(CSP_DB,
        "SELECT paid_to FROM csp_alloc WHERE pid=@p AND class=@c LIMIT 1");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    SqlBindInt(q, "@c", nClass);
    if (!SqlStep(q)) return nDefault;
    return SqlGetInt(q, 0);
}

int CSP_GetGranted(object oPC, int nClass)
{
    sqlquery q = SqlPrepareQueryCampaign(CSP_DB,
        "SELECT granted FROM csp_alloc WHERE pid=@p AND class=@c LIMIT 1");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    SqlBindInt(q, "@c", nClass);
    if (!SqlStep(q)) return 0;
    return SqlGetInt(q, 0);
}

// Write the high-water mark and the running total of picks granted.
//
// MAX() in the UPDATE is the belt-and-braces half of the anti-farm rule: even
// if a caller ever computed a lower paid_to (a de-levelled character, a bug),
// the stored mark cannot go backwards, so no level can be paid for twice.
void CSP_SetAlloc(object oPC, int nClass, int nPaidTo, int nGranted)
{
    sqlquery q = SqlPrepareQueryCampaign(CSP_DB,
        "INSERT INTO csp_alloc(pid, class, paid_to, granted, cdkey)" +
        " VALUES(@p, @c, @t, @g, @k)" +
        " ON CONFLICT(pid, class) DO UPDATE SET" +
        " paid_to=MAX(csp_alloc.paid_to, excluded.paid_to)," +
        " granted=MAX(csp_alloc.granted, excluded.granted)," +
        " updated_at=CURRENT_TIMESTAMP");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    SqlBindInt(q, "@c", nClass);
    SqlBindInt(q, "@t", nPaidTo);
    SqlBindInt(q, "@g", nGranted);
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlStep(q);
}

// Picks spent = spells this system has granted. Counted from the rows rather
// than kept as a number, so the ledger cannot drift from what was handed out.
int CSP_GetSpent(object oPC, int nClass)
{
    sqlquery q = SqlPrepareQueryCampaign(CSP_DB,
        "SELECT COUNT(*) FROM csp_learn WHERE pid=@p AND class=@c");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    SqlBindInt(q, "@c", nClass);
    if (!SqlStep(q)) return 0;
    return SqlGetInt(q, 0);
}

// INSERT OR IGNORE: the same spell twice is a no-op, not a second charge.
void CSP_RecordLearn(object oPC, int nClass, int nSpellId)
{
    sqlquery q = SqlPrepareQueryCampaign(CSP_DB,
        "INSERT OR IGNORE INTO csp_learn(pid, class, spell, cdkey)" +
        " VALUES(@p, @c, @s, @k)");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    SqlBindInt(q, "@c", nClass);
    SqlBindInt(q, "@s", nSpellId);
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlStep(q);
}

int CSP_HasLearn(object oPC, int nClass, int nSpellId)
{
    sqlquery q = SqlPrepareQueryCampaign(CSP_DB,
        "SELECT 1 FROM csp_learn WHERE pid=@p AND class=@c AND spell=@s LIMIT 1");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    SqlBindInt(q, "@c", nClass);
    SqlBindInt(q, "@s", nSpellId);
    return SqlStep(q);
}
