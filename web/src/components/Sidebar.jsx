import { NavLink } from "react-router-dom";

function Sidebar() {
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
      </nav>

      {/* Sign out needs to be implemented with auth context and routing to login page */}
      <div className="sidebar-footer">
        <button type="button">
          Sign Out
        </button>
      </div>
    </aside>
  );
}

export default Sidebar;