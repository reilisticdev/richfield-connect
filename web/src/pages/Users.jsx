import { useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";

const ROLES = ["student", "alumni", "business", "administrator"];
const STATUSES = ["active", "pending", "suspended", "rejected"];

const roleLabel = (role) =>
  role === "business" ? "Employer" : role.charAt(0).toUpperCase() + role.slice(1);

// Reuses the Moderation page's badge colours.
const badgeClass = (status) =>
  ({ active: "approved", pending: "pending", suspended: "rejected", rejected: "rejected" })[status] ??
  "pending";

const fullName = (member) =>
  `${member.first_name ?? ""} ${member.last_name ?? ""}`.trim() || "Unnamed member";

function Users() {
  const [members, setMembers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [roleFilter, setRoleFilter] = useState("all");
  const [statusFilter, setStatusFilter] = useState("all");
  const [search, setSearch] = useState("");
  const [busyId, setBusyId] = useState(null);

  useEffect(() => {
    let cancelled = false;

    const load = async () => {
      const { data, error } = await supabase
        .from("profiles")
        .select("id, first_name, last_name, email, role, account_status, created_at")
        .order("created_at", { ascending: false });

      if (cancelled) return;
      if (error) {
        console.error("Error loading members:", error);
        setError("Could not load members.");
      } else {
        setMembers(data || []);
      }
      setLoading(false);
    };

    load();
    return () => {
      cancelled = true;
    };
  }, []);

  const visible = useMemo(() => {
    const query = search.trim().toLowerCase();
    return members.filter(
      (member) =>
        (roleFilter === "all" || member.role === roleFilter) &&
        (statusFilter === "all" || member.account_status === statusFilter) &&
        (!query ||
          fullName(member).toLowerCase().includes(query) ||
          (member.email ?? "").toLowerCase().includes(query))
    );
  }, [members, roleFilter, statusFilter, search]);

  const counts = useMemo(
    () =>
      STATUSES.reduce(
        (acc, status) => ({
          ...acc,
          [status]: members.filter((member) => member.account_status === status).length,
        }),
        {}
      ),
    [members]
  );

  const setStatus = async (member, suspend) => {
    const name = fullName(member);
    let reason = null;

    if (suspend) {
      reason = window.prompt(
        `Suspend ${name}? They are signed out and can't sign in until reactivated.\n\nReason (kept in the admin log):`,
        ""
      );
      if (reason === null) return;
    } else if (!window.confirm(`Reactivate ${name}? They will be able to sign in again.`)) {
      return;
    }

    setError(null);
    setBusyId(member.id);
    const { error } = await supabase.rpc("admin_set_account_status", {
      target_id: member.id,
      suspend,
      reason,
    });
    setBusyId(null);

    if (error) {
      console.error("Error updating account status:", error);
      setError(error.message || "Could not update the account.");
      return;
    }

    setMembers((current) =>
      current.map((item) =>
        item.id === member.id
          ? { ...item, account_status: suspend ? "suspended" : "active" }
          : item
      )
    );
  };

  const remove = async (member) => {
    const name = fullName(member);
    if (
      !window.confirm(
        `Remove ${name}'s account permanently?\n\nTheir profile, posts, comments, connections, messages and applications are deleted. This can't be undone.`
      )
    ) {
      return;
    }
    const reason = window.prompt("Reason (kept in the admin log):", "");
    if (reason === null) return;

    setError(null);
    setBusyId(member.id);
    const { error } = await supabase.rpc("admin_remove_account", {
      target_id: member.id,
      reason,
    });
    setBusyId(null);

    if (error) {
      console.error("Error removing account:", error);
      setError(error.message || "Could not remove the account.");
      return;
    }

    setMembers((current) => current.filter((item) => item.id !== member.id));
  };

  return (
    <div className="admin-page">
      <div className="page-header">
        <div>
          <h1>Users</h1>
          <p>
            Every account on Richfield Connect. Suspend or remove a member here;
            business approvals and alumni verification are on the Moderation page.
          </p>
        </div>
      </div>

      {error && <p className="form-error">{error}</p>}

      <section className="admin-section">
        <div className="section-header">
          <div>
            <h2>Members</h2>
            <p>
              {counts.active ?? 0} active · {counts.pending ?? 0} pending ·{" "}
              {counts.suspended ?? 0} suspended · {counts.rejected ?? 0} rejected
            </p>
          </div>

          <span className="count-badge">{visible.length} Shown</span>
        </div>

        <div className="users-filters">
          <input
            type="search"
            placeholder="Search name or email"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
          />
          <select value={roleFilter} onChange={(event) => setRoleFilter(event.target.value)}>
            <option value="all">All roles</option>
            {ROLES.map((role) => (
              <option key={role} value={role}>
                {roleLabel(role)}
              </option>
            ))}
          </select>
          <select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)}>
            <option value="all">All statuses</option>
            {STATUSES.map((status) => (
              <option key={status} value={status}>
                {status.charAt(0).toUpperCase() + status.slice(1)}
              </option>
            ))}
          </select>
        </div>

        <div className="moderation-table">
          <div className="table-header">
            <span>Member</span>
            <span>Role</span>
            <span>Status</span>
            <span>Actions</span>
          </div>

          {loading ? (
            <div className="table-row">
              <div>Loading...</div>
            </div>
          ) : visible.length === 0 ? (
            <div className="table-row">
              <div>
                <strong>No members match</strong>
                <small>Try a different search or filter.</small>
              </div>
            </div>
          ) : (
            visible.map((member) => (
              <div className="table-row" key={member.id}>
                <div>
                  <strong>{fullName(member)}</strong>
                  <small>
                    {member.email} · joined {new Date(member.created_at).toLocaleDateString()}
                  </small>
                </div>

                <div>{roleLabel(member.role)}</div>

                <div>
                  <span className={`status-badge ${badgeClass(member.account_status)}`}>
                    {member.account_status}
                  </span>
                </div>

                <div className="action-buttons">
                  {member.role === "administrator" ? (
                    <small>Provisioned separately</small>
                  ) : (
                    <>
                      {member.account_status === "active" && (
                        <button
                          className="reject-button"
                          disabled={busyId === member.id}
                          onClick={() => setStatus(member, true)}
                        >
                          Suspend
                        </button>
                      )}
                      {member.account_status === "suspended" && (
                        <button
                          className="approve-button"
                          disabled={busyId === member.id}
                          onClick={() => setStatus(member, false)}
                        >
                          Reactivate
                        </button>
                      )}
                      <button
                        className="reject-button"
                        disabled={busyId === member.id}
                        onClick={() => remove(member)}
                      >
                        Remove
                      </button>
                    </>
                  )}
                </div>
              </div>
            ))
          )}
        </div>
      </section>
    </div>
  );
}

export default Users;
