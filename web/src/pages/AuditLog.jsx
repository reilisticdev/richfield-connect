import { useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";

// Read-only view over the two admin audit tables. Both are written only by
// the admin RPCs (suspend/reactivate/remove in migration 033, the
// verification approve/reject functions in 007) and readable only by
// administrators, so this page never writes anything.
//
// account_actions keeps its row when the member (or the administrator) is
// later removed: profile_id/admin_id are ON DELETE SET NULL, and
// target_label ("student · Jane Doe") is the name that survives.

// Reuses the Moderation page's badge colours.
const ACTION_BADGE = { suspended: "rejected", reactivated: "approved", removed: "removed" };
const DECISION_BADGE = { approved: "approved", rejected: "rejected", pending: "pending" };

const capitalise = (text) => text.charAt(0).toUpperCase() + text.slice(1);

const personName = (profile) =>
  profile ? `${profile.first_name ?? ""} ${profile.last_name ?? ""}`.trim() : "";

const when = (iso) =>
  new Date(iso).toLocaleString("en-ZA", { dateStyle: "medium", timeStyle: "short" });

// Alumni decisions carry claim_id, business decisions carry business_id.
const decisionSubject = (entry) => {
  if (entry.claim) {
    return {
      name: personName(entry.claim.profiles) || "Alumni member",
      detail: `Alumni claim · student no. ${entry.claim.student_number} · ${entry.claim.programme} (${entry.claim.graduation_year})`,
    };
  }
  if (entry.business) {
    const contact = personName(entry.business);
    return {
      name: entry.business.business_profiles?.company_name || contact || "Business",
      detail: `Business account${contact ? ` · ${contact}` : ""}`,
    };
  }
  return { name: "Account no longer exists", detail: "The member was removed after this decision" };
};

function AuditLog() {
  const [actions, setActions] = useState([]);
  const [decisions, setDecisions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [search, setSearch] = useState("");

  useEffect(() => {
    let cancelled = false;

    const load = async () => {
      // Each table has two foreign keys into profiles, so the embeds name
      // the column they follow (PostgREST's `!column` hint).
      const [actionsResult, decisionsResult] = await Promise.all([
        supabase
          .from("account_actions")
          .select(
            "id, action, target_label, reason, created_at, profile_id, admin:profiles!admin_id(first_name, last_name), target:profiles!profile_id(first_name, last_name)"
          )
          .order("created_at", { ascending: false })
          .limit(200),
        supabase
          .from("verification_audit")
          .select(
            "id, decision, reason, decided_at, admin:profiles!admin_id(first_name, last_name), business:profiles!business_id(first_name, last_name, business_profiles(company_name)), claim:verification_claims(student_number, programme, graduation_year, profiles(first_name, last_name))"
          )
          .order("decided_at", { ascending: false })
          .limit(200),
      ]);

      if (cancelled) return;
      if (actionsResult.error || decisionsResult.error) {
        console.error(
          "Error loading audit log:",
          actionsResult.error || decisionsResult.error
        );
        setError("Could not load the audit log.");
      }
      setActions(actionsResult.data || []);
      setDecisions(decisionsResult.data || []);
      setLoading(false);
    };

    load();
    return () => {
      cancelled = true;
    };
  }, []);

  const query = search.trim().toLowerCase();

  const visibleActions = useMemo(
    () =>
      actions.filter(
        (entry) =>
          !query ||
          [personName(entry.target), entry.target_label, entry.reason, personName(entry.admin)].some(
            (field) => (field ?? "").toLowerCase().includes(query)
          )
      ),
    [actions, query]
  );

  const visibleDecisions = useMemo(
    () =>
      decisions.filter((entry) => {
        if (!query) return true;
        const subject = decisionSubject(entry);
        return [subject.name, subject.detail, entry.reason, personName(entry.admin)].some(
          (field) => (field ?? "").toLowerCase().includes(query)
        );
      }),
    [decisions, query]
  );

  return (
    <div className="admin-page">
      <div className="page-header">
        <div>
          <h1>Audit Log</h1>
          <p>
            Every account suspension, reactivation and removal, and every
            verification decision, with who made it and why. Read-only.
          </p>
        </div>
      </div>

      {error && <p className="form-error">{error}</p>}

      <section className="admin-section">
        <div className="section-header">
          <div>
            <h2>Account Actions</h2>
            <p>Suspensions, reactivations and removals from the Users page.</p>
          </div>

          <span className="count-badge">{visibleActions.length} Entries</span>
        </div>

        <div className="users-filters">
          <input
            type="search"
            placeholder="Search member, reason or administrator"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
          />
        </div>

        <div className="moderation-table">
          <div className="table-header">
            <span>Member</span>
            <span>Action</span>
            <span>Administrator</span>
            <span>When</span>
          </div>

          {loading ? (
            <div className="table-row">
              <div>Loading...</div>
            </div>
          ) : visibleActions.length === 0 ? (
            <div className="table-row">
              <div>
                <strong>No account actions</strong>
                <small>
                  {query
                    ? "Nothing matches your search."
                    : "No account has been suspended, reactivated or removed yet."}
                </small>
              </div>
            </div>
          ) : (
            visibleActions.map((entry) => (
              <div className="table-row" key={entry.id}>
                <div>
                  <strong>{personName(entry.target) || entry.target_label}</strong>
                  <small>
                    {entry.target
                      ? entry.target_label
                      : entry.profile_id
                        ? "Profile not visible"
                        : "Account since removed"}
                  </small>
                </div>

                <div>
                  <span className={`status-badge ${ACTION_BADGE[entry.action] ?? "pending"}`}>
                    {capitalise(entry.action)}
                  </span>
                  <small>{entry.reason || "No reason recorded"}</small>
                </div>

                <div>{personName(entry.admin) || "Administrator since removed"}</div>

                <div>{when(entry.created_at)}</div>
              </div>
            ))
          )}
        </div>
      </section>

      <section className="admin-section">
        <div className="section-header">
          <div>
            <h2>Verification Decisions</h2>
            <p>Alumni claims and business accounts approved or rejected in Moderation.</p>
          </div>

          <span className="count-badge">{visibleDecisions.length} Entries</span>
        </div>

        <div className="moderation-table">
          <div className="table-header">
            <span>Member</span>
            <span>Decision</span>
            <span>Administrator</span>
            <span>When</span>
          </div>

          {loading ? (
            <div className="table-row">
              <div>Loading...</div>
            </div>
          ) : visibleDecisions.length === 0 ? (
            <div className="table-row">
              <div>
                <strong>No verification decisions</strong>
                <small>
                  {query
                    ? "Nothing matches your search."
                    : "No alumni claim or business account has been decided yet."}
                </small>
              </div>
            </div>
          ) : (
            visibleDecisions.map((entry) => {
              const subject = decisionSubject(entry);
              return (
                <div className="table-row" key={entry.id}>
                  <div>
                    <strong>{subject.name}</strong>
                    <small>{subject.detail}</small>
                  </div>

                  <div>
                    <span className={`status-badge ${DECISION_BADGE[entry.decision] ?? "pending"}`}>
                      {capitalise(entry.decision)}
                    </span>
                    <small>{entry.reason || "No reason recorded"}</small>
                  </div>

                  <div>{personName(entry.admin) || "Administrator"}</div>

                  <div>{when(entry.decided_at)}</div>
                </div>
              );
            })
          )}
        </div>
      </section>
    </div>
  );
}

export default AuditLog;
