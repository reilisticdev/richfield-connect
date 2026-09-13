import { useEffect, useState } from "react";
import {
  PieChart,
  Pie,
  Cell,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from "recharts";
import { supabase } from "../lib/supabase";

function formatLabel(value) {
  return value.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

const ROLE_COLORS = {
  student: "#2563eb",
  alumni: "#8b5cf6",
  business: "#14b8a6",
  administrator: "#334155",
};

const STATUS_COLORS = {
  active: "#22c55e",
  pending: "#f59e0b",
  suspended: "#ef4444",
  rejected: "#64748b",
};

function Analytics() {
  const [userCounts, setUserCounts] = useState([]);
  const [businessStatus, setBusinessStatus] = useState([]);
  const [engagement, setEngagement] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;

    const fetchAnalytics = async () => {
      setLoading(true);
      setError(null);

      // All three RPCs already exist (018_analytics_views.sql) and are
      // already locked to admins only (each self-checks is_admin()) - no
      // new backend work needed for this page.
      const [roles, businessPipeline, contentVolume] = await Promise.all([
        supabase.rpc("get_admin_user_counts"),
        supabase.rpc("get_admin_business_pipeline"),
        supabase.rpc("get_admin_content_volume"),
      ]);

      const firstError = [roles, businessPipeline, contentVolume].find(
        (result) => result.error
      )?.error;

      if (firstError) {
        console.error("Error loading analytics:", firstError);
        if (!cancelled) {
          setError("Could not load analytics data.");
          setLoading(false);
        }
        return;
      }

      if (!cancelled) {
        setUserCounts(
          (roles.data || []).map((row) => ({
            name: formatLabel(row.role),
            value: Number(row.total),
            color: ROLE_COLORS[row.role] ?? "#94a3b8",
          }))
        );

        setBusinessStatus(
          (businessPipeline.data || []).map((row) => ({
            name: formatLabel(row.status),
            total: Number(row.total),
            color: STATUS_COLORS[row.status] ?? "#94a3b8",
          }))
        );

        const volume = contentVolume.data?.[0] ?? {
          post_count: 0,
          video_count: 0,
          opportunity_count: 0,
        };
        setEngagement([
          { name: "Posts", total: Number(volume.post_count) },
          { name: "Videos", total: Number(volume.video_count) },
          { name: "Opportunities", total: Number(volume.opportunity_count) },
        ]);

        setLoading(false);
      }
    };

    fetchAnalytics();

    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <div className="admin-page">
      <div className="analytics-header">
         <div>
           <h1>Platform Analytics</h1>
           <p>
           Real-time overview of users, business accounts, and platform activity.
          </p>
     </div>

  <div className="analytics-live">
    <span className="analytics-live-dot"></span>
    Live data
  </div>
</div>

      {error && <p className="form-error">{error}</p>}

      <div className="charts-grid">
        <section className="admin-section chart-card">
          <div className="section-header">
           <div>
             <h2>Total Users by Role</h2>
             <p>Every registered profile, grouped by account type.</p>
           </div>

           <strong className="chart-summary">
            {userCounts.reduce((sum, item) => sum + item.value, 0)}
           </strong>
        </div>

          <div className="chart-body">
            {loading ? (
              <p className="chart-placeholder">Loading...</p>
            ) : userCounts.length === 0 ? (
              <p className="chart-placeholder">No users yet.</p>
            ) : (
              <ResponsiveContainer width="100%" height={280}>
                <PieChart>
                  <Pie
                    data={userCounts}
                    dataKey="value"
                    nameKey="name"
                    innerRadius={55}
                    outerRadius={90}
                    paddingAngle={2}
                  >
                    {userCounts.map((entry) => (
                      <Cell key={entry.name} fill={entry.color} />
                    ))}
                  </Pie>
                  <Tooltip
                    contentStyle={{
                      backgroundColor: "var(--chart-tooltip-bg)",
                      border: "1px solid var(--chart-tooltip-border)",
                      borderRadius: "10px",
                      boxShadow: "0 8px 20px rgba(15, 23, 42, 0.08)",
                    }}
                 />
                  <Legend
                     verticalAlign="bottom"
                     height={36}
                     iconType="circle"
                     wrapperStyle={{
                     fontSize: "13px",
                     color: "var(--chart-axis)",
                     paddingTop: "10px",
                     }}
                  />
                </PieChart>
              </ResponsiveContainer>
            )}
          </div>
        </section>

        <section className="admin-section chart-card">
          <div className="section-header">
            <div>
              <h2>Business Account Status</h2>
              <p>Where business accounts stand in the verification pipeline.</p>
            </div>
          </div>

          <div className="chart-body">
            {loading ? (
              <p className="chart-placeholder">Loading...</p>
            ) : businessStatus.length === 0 ? (
              <p className="chart-placeholder">No business accounts yet.</p>
            ) : (
              <ResponsiveContainer width="100%" height={280}>
                <BarChart data={businessStatus}>
                  <CartesianGrid
                    strokeDasharray="3 3"
                    stroke="var(--chart-grid)"
                    vertical={false}
                  />
                  <XAxis dataKey="name" tick={{ fontSize: 13, fill: "var(--chart-axis)" }} />
                  <YAxis
                     allowDecimals={false}
                     tick={{ fontSize: 12, fill: "var(--chart-axis)" }}
                     axisLine={false}
                     tickLine={false}
                  />
                 <Tooltip
                    contentStyle={{
                     backgroundColor: "var(--chart-tooltip-bg)",
                     border: "1px solid var(--chart-tooltip-border)",
                     borderRadius: "10px",
                     boxShadow: "0 8px 20px rgba(15, 23, 42, 0.08)",
                   }}
                  />
                  <Bar dataKey="total" radius={[6, 6, 0, 0]}>
                    {businessStatus.map((entry) => (
                      <Cell key={entry.name} fill={entry.color} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            )}
          </div>
        </section>

        <section className="admin-section chart-card chart-card-wide">
          <div className="section-header">
            <div>
              <h2>Platform Engagement</h2>
              <p>Total content created across the platform to date.</p>
            </div>
          </div>

          <div className="chart-body">
            {loading ? (
              <p className="chart-placeholder">Loading...</p>
            ) : (
              <ResponsiveContainer width="100%" height={280}>
                <BarChart data={engagement}>
                  <CartesianGrid
                    strokeDasharray="3 3"
                    stroke="var(--chart-grid)"
                    vertical={false}
                  />
                  <XAxis dataKey="name" tick={{ fontSize: 13, fill: "var(--chart-axis)" }} />
                  <YAxis
                     allowDecimals={false}
                     tick={{ fontSize: 12, fill: "var(--chart-axis)" }}
                     axisLine={false}
                     tickLine={false}
                  />
                  <Tooltip
                    contentStyle={{
                      backgroundColor: "var(--chart-tooltip-bg)",
                      border: "1px solid var(--chart-tooltip-border)",
                      borderRadius: "10px",
                      boxShadow: "0 8px 20px rgba(15, 23, 42, 0.08)",
                    }}
                  />
                  <Bar dataKey="total" fill="var(--chart-bar)" radius={[6, 6, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            )}
          </div>
        </section>
      </div>
    </div>
  );
}

export default Analytics;
