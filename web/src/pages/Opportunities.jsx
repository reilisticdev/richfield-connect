import { useState } from "react";

function Opportunities() {
  const [opportunities, setOpportunities] = useState([
    {
      id: 1,
      title: "Junior Data Analyst",
      company: "Example Technologies",
      type: "Internship",
      submitted: "2 September 2026",
      status: "Pending",
    },
    {
      id: 2,
      title: "Software Developer Intern",
      company: "Sample Digital Solutions",
      type: "Internship",
      submitted: "3 September 2026",
      status: "Pending",
    },
    {
      id: 3,
      title: "Marketing Assistant",
      company: "Example Marketing",
      type: "Part-time",
      submitted: "4 September 2026",
      status: "Pending",
    },
  ]);

  const updateOpportunityStatus = (id, status) => {
    setOpportunities((current) =>
      current.map((opportunity) =>
        opportunity.id === id
          ? { ...opportunity, status }
          : opportunity
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
                (opportunity) => opportunity.status === "Pending"
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

          {opportunities.map((opportunity) => (
            <div className="table-row" key={opportunity.id}>
              <div>
                <strong>{opportunity.title}</strong>
                <small>
                  Submitted {opportunity.submitted}
                </small>
              </div>

              <div>{opportunity.company}</div>

              <div>
                <span
                  className={`status-badge ${opportunity.status.toLowerCase()}`}
                >
                  {opportunity.status}
                </span>
              </div>

              <div className="action-buttons">
                <button
                  className="approve-button"
                  onClick={() =>
                    updateOpportunityStatus(
                      opportunity.id,
                      "Approved"
                    )
                  }
                >
                  Approve
                </button>

                <button
                  className="reject-button"
                  onClick={() =>
                    updateOpportunityStatus(
                      opportunity.id,
                      "Rejected"
                    )
                  }
                >
                  Reject
                </button>
              </div>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}

export default Opportunities;