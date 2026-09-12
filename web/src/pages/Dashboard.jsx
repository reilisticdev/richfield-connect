import { useEffect, useState } from "react";
import StatCard from "../components/StatCard";
import { supabase } from "../lib/supabase";

function Dashboard() {
  const [stats, setStats] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;

    const fetchStats = async () => {
      setError(null);

      const [ mau, pipeline, pendingClaims, flagged, publishedOpportunities, events,] = await Promise.all([
          supabase.rpc("get_admin_mau"),
          supabase.rpc("get_admin_business_pipeline"),
          supabase
            .from("verification_claims")
            .select("id", { count: "exact", head: true })
            .eq("status", "pending"),
          supabase.rpc("get_admin_flagged_content_count"),
          supabase
            .from("opportunities")
            .select("id, status"),
          supabase
            .from("events")
            .select("id, status"),
        ]);

      const firstError = [
        mau,
        pipeline,
        pendingClaims,
        flagged,
        publishedOpportunities,
        events,
      ].find((result) => result.error)?.error;

      if (firstError) {
        console.error("Error loading dashboard stats:", firstError);
        if (!cancelled) setError("Could not load dashboard stats.");
        return;
      }

      const pendingBusinesses =
        (pipeline.data || []).find((row) => row.status === "pending")
          ?.total ?? 0;
 
      const pendingOpportunities =
         (publishedOpportunities.data || []).filter(
         (opportunity) => opportunity.status === "pending"
         ).length;

      const publishedEvents =
         (events.data || []).filter((event) => event.status === "published").length;

      const draftEvents =
         (events.data || []).filter((event) => event.status === "draft").length;

      if (!cancelled) {
        setStats({
          activeUsers: mau.data ?? 0,
          pendingApprovals:
            Number(pendingBusinesses) + Number(pendingClaims.count ?? 0),
          flaggedContent: flagged.data ?? 0,
          publishedOpportunities: (publishedOpportunities.data || []).filter(
             (opportunity) => opportunity.status === "approved"
             ).length,
             pendingOpportunities: pendingOpportunities,
          events: {
              total: events.data?.length ?? 0,
             published: publishedEvents,
             drafts: draftEvents,
          },
        });
      }
    };

    fetchStats();

    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <div className="dashboard-page">
      <div className="dashboard-header">
        <div>
          <h1>Admin Dashboard</h1>
          <p>Overview of the Richfield Connect platform.</p>
        </div>
      </div>

      {error && <p className="form-error">{error}</p>}

      <div className="stats-grid">
        <StatCard
          title="Total Active Users"
          value={stats ? stats.activeUsers : "—"}
          description="All user types"
        />

        <StatCard
          title="Pending Approvals"
          value={stats ? stats.pendingApprovals : "—"}
          description="Business & alumni"
        />

        <StatCard
          title="Flagged Content"
          value={stats ? stats.flaggedContent : "—"}
          description="Requires review"
        />

       <StatCard
         title="Opportunities"
         value={
           stats
             ? stats.publishedOpportunities + stats.pendingOpportunities
             : "—"
          }
         description={
            stats
               ? `${stats.publishedOpportunities} Published · ${stats.pendingOpportunities} Pending`
               : "Loading..."
          }
       />

        <StatCard
           title="Events"
           value={stats ? stats.events.total : "—"}
           description={
             stats
               ? `${stats.events.published} Published · ${stats.events.drafts} Drafts`
               : "Loading..."
           }
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
