import { useNavigate } from "react-router-dom";
import { Button } from "@/components/ui/button";

const Orders = () => {
  const navigate = useNavigate();
  return (
    <div className="p-8 text-center space-y-4">
      <h1 className="text-xl font-bold">Orders Management</h1>
      <p className="text-slate-500">This module is deprecated in DocumentVault.</p>
      <Button onClick={() => navigate("/dashboard")} className="bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl">
        Back to Dashboard
      </Button>
    </div>
  );
};

export default Orders;
