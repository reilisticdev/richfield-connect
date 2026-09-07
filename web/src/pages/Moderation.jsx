import { useEffect, useState } from "react";
import { supabase } from "../lib/supabase";

function Moderation() {
  const [businesses, setBusinesses] = useState([]);
  const [loadingBusinesses, setLoadingBusinesses] = useState(true);

  const [alumni, setAlumni] = useState([
    {
      id: 1,
      name: "Example Alumni",
      verification: "Richfield student record",
      status: "Pending",
    },
    {
      id: 2,
      name: "Sample Alumni",
      verification: "Identity verification",
      status: "Pending",
    },
  ]);

  const [flaggedContent, setFlaggedContent] = useState([
    {
      id: 1,
      content: "Reported post",
      reportedBy: "Student user",
      reason: "Under Review",
      status: "Flagged",
    },
  ]);

  useEffect(() => {
    fetchPendingBusinesses();
  }, []);

  const fetchPendingBusinesses = async () => {
    setLoadingBusinesses(true);

    const { data, error } = await supabase
      .from("profiles")
      .select("id, first_name, last_name, email, account_status")
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

  const updateBusinessStatus = async (id, status) => {
    const accountStatus =
      status === "Approved" ? "active" : "rejected";

    const { error } = await supabase
      .from("profiles")
      .update({ account_status: accountStatus })
      .eq("id", id);

    if (error) {
      console.error("Error updating business status:", error);
      return;
    }

    setBusinesses((current) =>
      current.filter((business) => business.id !== id)
    );
  };

  const updateAlumniStatus = (id, status) => {
    setAlumni((current) =>
      current.map((person) =>
        person.id === id ? { ...person, status } : person
      )
    );
  };

  const updateContentStatus = (id, status) => {
    setFlaggedContent((current) =>
      current.map((content) =>
        content.id === id ? { ...content, status } : content
      )
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
                    {business.first_name} {business.last_name}
                  </strong>
                  <small>Business registration</small>
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
            {alumni.filter((person) => person.status === "Pending").length}{" "}
            Pending
          </span>
        </div>

        <div className="moderation-table">
          <div className="table-header">
            <span>Alumni</span>
            <span>Verification</span>
            <span>Status</span>
            <span>Actions</span>
          </div>

          {alumni.map((person) => (
            <div className="table-row" key={person.id}>
              <div>
                <strong>{person.name}</strong>
                <small>Alumni verification request</small>
              </div>

              <div>{person.verification}</div>

              <div>
                <span className={`status-badge ${person.status.toLowerCase()}`}>
                  {person.status}
                </span>
              </div>

              <div className="action-buttons">
                <button
                  className="approve-button"
                  onClick={() =>
                    updateAlumniStatus(person.id, "Approved")
                  }
                >
                  Approve
                </button>

                <button
                  className="reject-button"
                  onClick={() =>
                    updateAlumniStatus(person.id, "Rejected")
                  }
                >
                  Reject
                </button>
              </div>
            </div>
          ))}
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
            {flaggedContent.filter(
              (content) => content.status === "Flagged"
            ).length}{" "}
            Review
          </span>
        </div>

        <div className="moderation-table">
          <div className="table-header">
            <span>Content</span>
            <span>Reported By</span>
            <span>Reason</span>
            <span>Actions</span>
          </div>

          {flaggedContent.map((content) => (
            <div className="table-row" key={content.id}>
              <div>
                <strong>{content.content}</strong>
                <small>Community post</small>
              </div>

              <div>{content.reportedBy}</div>

              <div>
                <span
                  className={`status-badge ${content.status.toLowerCase()}`}
                >
                  {content.status}
                </span>
              </div>

              <div className="action-buttons">
                <button
                  className="approve-button"
                  onClick={() =>
                    updateContentStatus(content.id, "Kept")
                  }
                >
                  Keep
                </button>

                <button
                  className="reject-button"
                  onClick={() =>
                    updateContentStatus(content.id, "Removed")
                  }
                >
                  Remove
                </button>
              </div>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}

export default Moderation;

