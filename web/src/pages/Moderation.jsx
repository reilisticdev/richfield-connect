import { useEffect, useState } from "react";
import { supabase } from "../lib/supabase";

function Moderation() {
  const [businesses, setBusinesses] = useState([]);
  const [loadingBusinesses, setLoadingBusinesses] = useState(true);

  const [alumni, setAlumni] = useState([]);
  const [loadingAlumni, setLoadingAlumni] = useState(true);

  const [flaggedContent, setFlaggedContent] = useState([]);
  const [loadingFlagged, setLoadingFlagged] = useState(true);

  const [error, setError] = useState(null);

  const fetchPendingBusinesses = async () => {
    setLoadingBusinesses(true);

    const { data, error } = await supabase
      .from("profiles")
      .select(
        "id, first_name, last_name, email, account_status, business_profiles(company_name)"
      )
      .eq("role", "business")
      .eq("account_status", "pending");

    if (error) {
      console.error("Error fetching pending businesses:", error);
      setBusinesses([]);
    } else {
      setBusinesses(data || []);
    }

    setLoadingBusinesses(false);
  };

  const fetchPendingAlumni = async () => {
    setLoadingAlumni(true);

    const { data, error } = await supabase
      .from("verification_claims")
      .select(
        "id, student_number, programme, campus, graduation_year, status, profiles(first_name, last_name, email)"
      )
      .eq("status", "pending");

    if (error) {
      console.error("Error fetching pending alumni claims:", error);
      setAlumni([]);
    } else {
      setAlumni(data || []);
    }

    setLoadingAlumni(false);
  };

  const fetchFlaggedContent = async () => {
    setLoadingFlagged(true);

    const { data, error } = await supabase
      .from("content_reports")
      .select(
        "id, content_id, content_type, reason, status, profiles(first_name, last_name)"
      )
      .eq("status", "pending");

    if (error) {
      console.error("Error fetching flagged content:", error);
      setFlaggedContent([]);
    } else {
      setFlaggedContent(data || []);
    }

    setLoadingFlagged(false);
  };

  useEffect(() => {
    fetchPendingBusinesses();
    fetchPendingAlumni();
    fetchFlaggedContent();
  }, []);

  const updateBusinessStatus = async (id, status) => {
    const { error } =
      status === "Approved"
        ? await supabase.rpc("approve_business_account", {
            target_business_id: id,
          })
        : await supabase.rpc("reject_business_account", {
            target_business_id: id,
            reason: null,
          });

    if (error) {
      console.error("Error updating business status:", error);
      setError("Could not update business account.");
      return;
    }

    setBusinesses((current) =>
      current.filter((business) => business.id !== id)
    );
  };

  const updateAlumniStatus = async (id, status) => {
    if (status === "Approved") {
      const { error } = await supabase.rpc("approve_alumni_verification", {
        claim_id: id,
      });

      if (error) {
        console.error("Error approving alumni verification:", error);
        setError("Could not approve alumni verification.");
        return;
      }
    } else {
      const reason =
        window.prompt(
          "Reason for rejection:",
          "Documentation did not match student record"
        ) ?? "Not specified";

      const { error } = await supabase.rpc("reject_alumni_verification", {
        claim_id: id,
        reason,
      });

      if (error) {
        console.error("Error rejecting alumni verification:", error);
        setError("Could not reject alumni verification.");
        return;
      }
    }

    setAlumni((current) => current.filter((person) => person.id !== id));
  };

  const updateContentStatus = async (id, status) => {
    const { error } = await supabase
      .from("content_reports")
      .update({ status })
      .eq("id", id);

    if (error) {
      console.error("Error updating flagged content:", error);
      setError("Could not update flagged content.");
      return;
    }

    setFlaggedContent((current) =>
      current.filter((content) => content.id !== id)
    );
  };

  return (
    <div className="admin-page">
      <div className="page-header">
        <div>
          <h1>Moderation</h1>
          <p>
            Review and manage pending accounts, alumni verification, and
            flagged content.
          </p>
        </div>
      </div>

      {error && <p className="form-error">{error}</p>}

      {/* Business Accounts */}
      <section className="admin-section">
        <div className="section-header">
          <div>
            <h2>Pending Business Accounts</h2>
            <p>Review businesses requesting access to Richfield Connect.</p>
          </div>

          <span className="count-badge">
            {businesses.length} Pending
          </span>
        </div>

        <div className="moderation-table">
          <div className="table-header">
            <span>Business</span>
            <span>Contact</span>
            <span>Status</span>
            <span>Actions</span>
          </div>

          {loadingBusinesses ? (
            <div className="table-row">
              <div>Loading...</div>
            </div>
          ) : businesses.length === 0 ? (
            <div className="table-row">
              <div>
                <strong>No pending business accounts</strong>
                <small>
                  There are currently no business registrations waiting for
                  approval.
                </small>
              </div>
            </div>
          ) : (
            businesses.map((business) => (
              <div className="table-row" key={business.id}>
                <div>
                  <strong>
                    {business.business_profiles?.company_name ??
                      `${business.first_name} ${business.last_name}`}
                  </strong>
                  <small>
                    {business.first_name} {business.last_name}
                  </small>
                </div>

                <div>{business.email}</div>

                <div>
                  <span className="status-badge pending">
                    Pending
                  </span>
                </div>

                <div className="action-buttons">
                  <button
                    className="approve-button"
                    onClick={() =>
                      updateBusinessStatus(business.id, "Approved")
                    }
                  >
                    Approve
                  </button>

                  <button
                    className="reject-button"
                    onClick={() =>
                      updateBusinessStatus(business.id, "Rejected")
                    }
                  >
                    Reject
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      </section>

      {/* Alumni Verification */}
      <section className="admin-section">
        <div className="section-header">
          <div>
            <h2>Alumni Verification</h2>
            <p>Review alumni claims and verify their identity.</p>
          </div>

          <span className="count-badge">
            {alumni.length} Pending
          </span>
        </div>

        <div className="moderation-table">
          <div className="table-header">
            <span>Alumni</span>
            <span>Verification</span>
            <span>Status</span>
            <span>Actions</span>
          </div>

          {loadingAlumni ? (
            <div className="table-row">
              <div>Loading...</div>
            </div>
          ) : alumni.length === 0 ? (
            <div className="table-row">
              <div>
                <strong>No alumni verification requests</strong>
                <small>
                  There are currently no alumni claims waiting for review.
                </small>
              </div>
            </div>
          ) : (
            alumni.map((claim) => (
              <div className="table-row" key={claim.id}>
                <div>
                  <strong>
                    {claim.profiles?.first_name} {claim.profiles?.last_name}
                  </strong>
                  <small>Student no. {claim.student_number}</small>
                </div>

                <div>
                  {claim.programme} — {claim.campus} ({claim.graduation_year})
                </div>

                <div>
                  <span className="status-badge pending">
                    Pending
                  </span>
                </div>

                <div className="action-buttons">
                  <button
                    className="approve-button"
                    onClick={() => updateAlumniStatus(claim.id, "Approved")}
                  >
                    Approve
                  </button>

                  <button
                    className="reject-button"
                    onClick={() => updateAlumniStatus(claim.id, "Rejected")}
                  >
                    Reject
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      </section>

      {/* Flagged Content */}
      <section className="admin-section">
        <div className="section-header">
          <div>
            <h2>Flagged Content</h2>
            <p>Review content that has been reported or flagged.</p>
          </div>

          <span className="count-badge">
            {flaggedContent.length} Review
          </span>
        </div>

        <div className="moderation-table">
          <div className="table-header">
            <span>Content</span>
            <span>Reported By</span>
            <span>Reason</span>
            <span>Actions</span>
          </div>

          {loadingFlagged ? (
            <div className="table-row">
              <div>Loading...</div>
            </div>
          ) : flaggedContent.length === 0 ? (
            <div className="table-row">
              <div>
                <strong>No flagged content</strong>
                <small>There is currently nothing waiting for review.</small>
              </div>
            </div>
          ) : (
            flaggedContent.map((content) => (
              <div className="table-row" key={content.id}>
                <div>
                  <strong>
                    {content.content_type} #{content.content_id.slice(0, 8)}
                  </strong>
                  <small>Community {content.content_type}</small>
                </div>

                <div>
                  {content.profiles
                    ? `${content.profiles.first_name} ${content.profiles.last_name}`
                    : "Unknown user"}
                </div>

                <div>{content.reason}</div>

                <div className="action-buttons">
                  <button
                    className="approve-button"
                    onClick={() => updateContentStatus(content.id, "dismissed")}
                  >
                    Keep
                  </button>

                  <button
                    className="reject-button"
                    onClick={() => updateContentStatus(content.id, "actioned")}
                  >
                    Remove
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      </section>
    </div>
  );
}

export default Moderation;
