import { NavLink, useNavigate } from "react-router-dom";
import { supabase } from "../lib/supabase";

function Sidebar() {
  const navigate = useNavigate();

  const handleSignOut = async () => {
    const { error } = await supabase.auth.signOut();

    if (error) {
      console.error("Sign out error:", error);
      return;
    }

    navigate("/login");
  };

  return (
    <aside className="sidebar">
      <div className="sidebar-brand">
        <h2>Richfield</h2>
        <span>Connect</span>
      </div>

      <nav className="sidebar-nav">
        <NavLink to="/dashboard">
          Dashboard
        </NavLink>

        <NavLink to="/users">
          Users
        </NavLink>

        <NavLink to="/analytics">
          Analytics
        </NavLink>

        <NavLink to="/moderation">
          Moderation
        </NavLink>

        <NavLink to="/opportunities">
          Opportunities
        </NavLink>

        <NavLink to="/events">
          Events
        </NavLink>

        <NavLink to="/announcements">
          Announcements
        </NavLink>

        <NavLink to="/audit-log">
          Audit Log
        </NavLink>
      </nav>

      <div className="sidebar-footer">
        <button type="button" onClick={handleSignOut}>
          Sign Out
        </button>
      </div>
    </aside>
  );
}

export default Sidebar;
