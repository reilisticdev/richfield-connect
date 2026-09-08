import StatCard from "../components/StatCard";

function Dashboard() {
  return (
    <div className="dashboard-page">
      <div className="dashboard-header">
        <div>
          <h1>Admin Dashboard</h1>
          <p>Overview of the Richfield Connect platform.</p>
        </div>
      </div>

      <div className="stats-grid">
        <StatCard
          title="Total Active Users"
          value="—"
          description="All user types"
        />

        <StatCard
          title="Pending Approvals"
          value="—"
          description="Business & alumni"
        />

        <StatCard
          title="Flagged Content"
          value="—"
          description="Requires review"
        />

        <StatCard
          title="Published Opportunities"
          value="—"
          description="Visible to students"
        />
      </div>

      <div className="dashboard-section">
        <h2>Platform Overview</h2>
        <p>
          Analytics and engagement information will appear here once the
          dashboard is connected to the Richfield Connect database.
        </p>
      </div>
    </div>
  );
}

export default Dashboard;