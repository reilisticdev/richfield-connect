import { useEffect, useState } from "react";
import { supabase } from "../lib/supabase";

function formatLabel(value) {
  return value.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

function Opportunities() {
  const [opportunities, setOpportunities] = useState([]);
  const [loadingOpportunities, setLoadingOpportunities] = useState(true);
  const [error, setError] = useState(null);

  const fetchOpportunities = async () => {
    setLoadingOpportunities(true);

    const { data, error } = await supabase
      .from("opportunities")
      .select(
        "id, title, opportunity_type, status, created_at, profiles:business_id(business_profiles(company_name))"
      )
      .order("created_at", { ascending: false });

    if (error) {
      console.error("Error fetching opportunities:", error);
      setError("Could not load opportunities.");
      setOpportunities([]);
    } else {
      setOpportunities(data || []);
    }

    setLoadingOpportunities(false);
  };

  useEffect(() => {
    fetchOpportunities();
  }, []);

  const updateOpportunityStatus = async (id, status) => {
    const { error } = await supabase
      .from("opportunities")
      .update({ status })
      .eq("id", id);

    if (error) {
      console.error("Error updating opportunity:", error);
      setError("Could not update opportunity.");
      return;
    }

    setOpportunities((current) =>
      current.map((opportunity) =>
        opportunity.id === id ? { ...opportunity, status } : opportunity
      )
    );
  };

  return (
    <div className="admin-page">
      <div className="page-header">
        <div>
          <h1>Opportunity Approval</h1>
          <p>
            Review business opportunity listings before they are published
            to students.
          </p>
        </div>
      </div>

      {error && <p className="form-error">{error}</p>}

      <section className="admin-section">
        <div className="section-header">
          <div>
            <h2>Pending Opportunities</h2>
            <p>
              Review and approve opportunities submitted by business users.
            </p>
          </div>

          <span className="count-badge">
            {
              opportunities.filter(
                (opportunity) => opportunity.status === "pending"
              ).length
            }{" "}
            Pending
          </span>
        </div>

        <div className="moderation-table">
          <div className="table-header">
            <span>Opportunity</span>
            <span>Company</span>
            <span>Type</span>
            <span>Actions</span>
          </div>

          {loadingOpportunities ? (
            <div className="table-row">
              <div>Loading...</div>
            </div>
          ) : opportunities.length === 0 ? (
            <div className="table-row">
              <div>
                <strong>No opportunities submitted</strong>
                <small>
                  Business opportunity listings will appear here for review.
                </small>
              </div>
            </div>
          ) : (
            opportunities.map((opportunity) => (
              <div className="table-row" key={opportunity.id}>
                <div>
                  <strong>{opportunity.title}</strong>
                  <small>
                    Submitted{" "}
                    {new Date(opportunity.created_at).toLocaleDateString(
                      "en-ZA",
                      { day: "numeric", month: "long", year: "numeric" }
                    )}
                  </small>
                </div>

                <div>
                  {opportunity.profiles?.business_profiles?.company_name ??
                    "Unknown company"}
                </div>

                <div>{formatLabel(opportunity.opportunity_type)}</div>

                <div className="action-buttons">
                  <span
                    className={`status-badge ${opportunity.status}`}
                  >
                    {formatLabel(opportunity.status)}
                  </span>

                  {opportunity.status === "pending" && (
                    <>
                      <button
                        className="approve-button"
                        onClick={() =>
                          updateOpportunityStatus(opportunity.id, "approved")
                        }
                      >
                        Approve
                      </button>

                      <button
                        className="reject-button"
                        onClick={() =>
                          updateOpportunityStatus(opportunity.id, "rejected")
                        }
                      >
                        Reject
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

export default Opportunities;
