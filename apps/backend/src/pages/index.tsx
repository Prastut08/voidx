import React, { useState, useEffect, useRef } from 'react';
import Head from 'next/head';

interface SOSRecord {
  sos_id: string;
  user_id?: string;
  category: string;
  description: string;
  latitude: number;
  longitude: number;
  severity: string;
  status: string;
  distance_from_responder_km?: number;
  timestamp?: string;
  created_at?: string;
}

export default function RescueDashboard() {
  const [role, setRole] = useState<'VOLUNTEER' | 'COORDINATOR' | 'RESCUE_TEAM' | 'ADMIN'>('VOLUNTEER');
  const [userId] = useState(() => 'RESP_' + Math.floor(1000 + Math.random() * 9000));
  const [coords, setCoords] = useState<{ lat: number; lng: number }>({ lat: 20.2961, lng: 85.8245 });
  const [isConnected, setIsConnected] = useState(false);
  const [incomingAlerts, setIncomingAlerts] = useState<SOSRecord[]>([]);
  const [activeSOSList, setActiveSOSList] = useState<SOSRecord[]>([]);
  const [acceptedSOS, setAcceptedSOS] = useState<SOSRecord | null>(null);
  const [logs, setLogs] = useState<string[]>([]);

  const wsRef = useRef<WebSocket | null>(null);

  // Auto-detect browser location dynamically
  useEffect(() => {
    if (typeof window !== 'undefined' && 'geolocation' in navigator) {
      navigator.geolocation.getCurrentPosition(
        (pos) => {
          setCoords({ lat: pos.coords.latitude, lng: pos.coords.longitude });
          addLog(`Device GPS locked: ${pos.coords.latitude.toFixed(4)}, ${pos.coords.longitude.toFixed(4)}`);
        },
        () => {
          addLog('Defaulting to monitoring station coordinates');
        }
      );
    }
  }, []);

  const addLog = (msg: string) => {
    setLogs((prev) => [new Date().toLocaleTimeString() + ' - ' + msg, ...prev.slice(0, 19)]);
  };

  // Connect WebSocket
  useEffect(() => {
    if (typeof window === 'undefined') return;

    // Use current host dynamically (support local network IP)
    const host = window.location.hostname || 'localhost';
    const wsUrl = `ws://${host}:8080/ws/rescue?user_id=${userId}&role=${role}&lat=${coords.lat}&lng=${coords.lng}`;

    addLog(`Connecting WebSocket: ${wsUrl}`);
    const ws = new WebSocket(wsUrl);
    wsRef.current = ws;

    ws.onopen = () => {
      setIsConnected(true);
      addLog(`Connected to CycloneX Emergency Mesh as ${role} (${userId})`);
    };

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);

        if (data.type === 'NEW_SOS_ALERT') {
          const newSos: SOSRecord = data.sos;
          addLog(`🚨 INCOMING SOS [${newSos.sos_id}] - ${newSos.category} (${newSos.distance_from_responder_km || 0}km away)`);
          
          // Trigger Emergency Audio Tone if permitted
          try {
            const ctx = new (window.AudioContext || (window as any).webkitAudioContext)();
            const osc = ctx.createOscillator();
            osc.type = 'sawtooth';
            osc.frequency.setValueAtTime(880, ctx.currentTime);
            osc.connect(ctx.destination);
            osc.start();
            osc.stop(ctx.currentTime + 0.35);
          } catch (_) {}

          // Add to popups list
          setIncomingAlerts((prev) => {
            if (prev.find((x) => x.sos_id === newSos.sos_id)) return prev;
            return [newSos, ...prev];
          });

          // Add to active SOS list
          setActiveSOSList((prev) => [newSos, ...prev.filter((x) => x.sos_id !== newSos.sos_id)]);
        } else if (data.type === 'PENDING_SOS_SYNC') {
          setActiveSOSList(data.requests || []);
          addLog(`Synchronized ${data.count} active pending SOS requests`);
        } else if (data.type === 'SOS_STATUS_UPDATE') {
          addLog(`Status Update: ${data.sos_id} -> ${data.status} by ${data.claimed_by || 'system'}`);
          if (data.status === 'ACCEPTED') {
            // Remove from alert popups if another responder accepted it
            setIncomingAlerts((prev) => prev.filter((x) => x.sos_id !== data.sos_id));
          }
          setActiveSOSList((prev) =>
            prev.map((s) => (s.sos_id === data.sos_id ? { ...s, status: data.status } : s))
          );
        }
      } catch (err) {
        console.error('WS Parse Error', err);
      }
    };

    ws.onclose = () => {
      setIsConnected(false);
      addLog('WebSocket disconnected. Will retry connection...');
    };

    return () => {
      ws.close();
    };
  }, [role, coords.lat, coords.lng]);

  const handleAcceptSOS = async (sos: SOSRecord) => {
    try {
      const host = window.location.hostname || 'localhost';
      const res = await fetch(`http://${host}:8080/api/sos/${sos.sos_id}/accept`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          responder_id: userId,
          responder_name: `${role} Unit (${userId})`,
          responder_role: role,
        }),
      });

      const result = await res.json();
      if (result.success) {
        setAcceptedSOS(result.sos);
        setIncomingAlerts((prev) => prev.filter((x) => x.sos_id !== sos.sos_id));
        addLog(`✅ Successfully Claimed & Assigned to ${sos.sos_id}!`);
      } else {
        alert(result.message || 'SOS was already claimed by another responder.');
        setIncomingAlerts((prev) => prev.filter((x) => x.sos_id !== sos.sos_id));
      }
    } catch (e) {
      alert(`Accept Error: ${e}`);
    }
  };

  const dismissAlert = (sosId: string) => {
    setIncomingAlerts((prev) => prev.filter((x) => x.sos_id !== sosId));
  };

  return (
    <div className="min-h-screen bg-slate-900 text-slate-100 flex flex-col font-sans">
      <Head>
        <title>CycloneX Responder Dashboard</title>
      </Head>

      {/* EMERGENCY POPUP MODAL (Zero-refresh real-time push) */}
      {incomingAlerts.length > 0 && (
        <div className="fixed inset-0 z-50 bg-black/75 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-slate-800 border-2 border-red-500 rounded-2xl max-w-lg w-full p-6 shadow-2xl shadow-red-500/30 animate-bounce-once">
            <div className="flex items-center justify-between border-b border-slate-700 pb-3 mb-4">
              <div className="flex items-center gap-3">
                <span className="relative flex h-4 w-4">
                  <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75"></span>
                  <span className="relative inline-flex rounded-full h-4 w-4 bg-red-600"></span>
                </span>
                <h2 className="text-xl font-bold tracking-tight text-red-400">
                  CRITICAL RESCUE DISPATCH ALERT
                </h2>
              </div>
              <span className="bg-red-500/20 text-red-300 px-2.5 py-1 rounded-full text-xs font-semibold">
                {incomingAlerts[0].severity || 'HIGH'}
              </span>
            </div>

            <div className="space-y-3 mb-6">
              <div className="flex justify-between items-center text-sm">
                <span className="text-slate-400">Emergency ID:</span>
                <span className="font-mono font-bold text-white">{incomingAlerts[0].sos_id}</span>
              </div>
              <div className="flex justify-between items-center text-sm">
                <span className="text-slate-400">Category:</span>
                <span className="uppercase font-semibold text-amber-400">{incomingAlerts[0].category}</span>
              </div>
              <div className="flex justify-between items-center text-sm">
                <span className="text-slate-400">Distance From You:</span>
                <span className="font-bold text-emerald-400">
                  {incomingAlerts[0].distance_from_responder_km ?? 'Nearby'} km
                </span>
              </div>
              <div className="flex justify-between items-center text-sm">
                <span className="text-slate-400">Coordinates:</span>
                <span className="font-mono text-xs text-slate-300">
                  {incomingAlerts[0].latitude}, {incomingAlerts[0].longitude}
                </span>
              </div>
              <div className="bg-slate-900/80 p-3 rounded-lg border border-slate-700/60 mt-2">
                <p className="text-xs text-slate-400 mb-1 font-semibold uppercase">Victim Situation:</p>
                <p className="text-sm italic text-slate-200">"{incomingAlerts[0].description}"</p>
              </div>
            </div>

            <div className="flex items-center gap-3">
              <button
                onClick={() => handleAcceptSOS(incomingAlerts[0])}
                className="flex-1 bg-red-600 hover:bg-red-500 text-white font-bold py-3 px-4 rounded-xl shadow-lg shadow-red-600/40 transition duration-150 transform hover:-translate-y-0.5 text-center text-sm uppercase tracking-wider"
              >
                ACCEPT SOS & DISPATCH
              </button>
              <button
                onClick={() =>
                  window.open(
                    `https://www.google.com/maps/dir/?api=1&destination=${incomingAlerts[0].latitude},${incomingAlerts[0].longitude}`,
                    '_blank'
                  )
                }
                className="bg-slate-700 hover:bg-slate-600 text-white font-semibold py-3 px-4 rounded-xl text-sm"
              >
                Map
              </button>
              <button
                onClick={() => dismissAlert(incomingAlerts[0].sos_id)}
                className="bg-transparent hover:bg-slate-700 text-slate-400 hover:text-white py-3 px-3 rounded-xl text-sm"
              >
                Dismiss
              </button>
            </div>
          </div>
        </div>
      )}

      {/* TOP NAV BAR */}
      <header className="border-b border-slate-800 bg-slate-950/80 px-6 py-4 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="h-9 w-9 rounded-lg bg-red-600 flex items-center justify-center font-bold text-white shadow-md shadow-red-600/30">
            CX
          </div>
          <div>
            <h1 className="text-lg font-bold leading-tight">CycloneX Rescue Command Center</h1>
            <p className="text-xs text-slate-400">Real-Time D2D & Central Dispatch Mesh</p>
          </div>
        </div>

        <div className="flex items-center gap-4">
          <div className="flex items-center gap-2 bg-slate-800/80 px-3 py-1.5 rounded-lg border border-slate-700 text-xs">
            <span
              className={`h-2.5 w-2.5 rounded-full ${isConnected ? 'bg-emerald-500 animate-pulse' : 'bg-rose-500'}`}
            ></span>
            <span>{isConnected ? 'LIVE WS MESH CONNECTED' : 'DISCONNECTED'}</span>
          </div>

          <div className="flex items-center gap-2 bg-slate-800 px-3 py-1.5 rounded-lg border border-slate-700 text-xs">
            <span className="text-slate-400">Responder Role:</span>
            <select
              value={role}
              onChange={(e) => setRole(e.target.value as any)}
              className="bg-transparent text-white font-semibold focus:outline-none cursor-pointer"
            >
              <option value="VOLUNTEER" className="bg-slate-800">Volunteer</option>
              <option value="RESCUE_TEAM" className="bg-slate-800">Rescue Team</option>
              <option value="COORDINATOR" className="bg-slate-800">Coordinator</option>
              <option value="ADMIN" className="bg-slate-800">Admin</option>
            </select>
          </div>
        </div>
      </header>

      {/* MAIN GRID */}
      <div className="flex-1 p-6 grid grid-cols-1 lg:grid-cols-3 gap-6 max-w-7xl mx-auto w-full">
        {/* Left Column: Claimed / Active Requests */}
        <div className="lg:col-span-2 space-y-6">
          {acceptedSOS && (
            <div className="bg-emerald-950/40 border border-emerald-500/50 rounded-2xl p-5 shadow-lg">
              <div className="flex items-center justify-between mb-3">
                <span className="bg-emerald-500/20 text-emerald-300 font-bold px-3 py-1 rounded-full text-xs">
                  CURRENTLY ASSIGNED TO YOU
                </span>
                <span className="font-mono text-sm font-semibold">{acceptedSOS.sos_id}</span>
              </div>
              <h3 className="text-xl font-bold text-white mb-1">{acceptedSOS.category} EMERGENCY</h3>
              <p className="text-slate-300 text-sm mb-4">{acceptedSOS.description}</p>
              <div className="flex gap-3">
                <button
                  onClick={() =>
                    window.open(
                      `https://www.google.com/maps/dir/?api=1&destination=${acceptedSOS.latitude},${acceptedSOS.longitude}`,
                      '_blank'
                    )
                  }
                  className="bg-emerald-600 hover:bg-emerald-500 text-white font-semibold px-4 py-2 rounded-lg text-sm flex items-center gap-2"
                >
                  Open Live GPS Navigation
                </button>
              </div>
            </div>
          )}

          <div className="bg-slate-800/60 rounded-2xl border border-slate-700 p-5">
            <h2 className="text-lg font-bold mb-4 flex items-center justify-between">
              <span>Active SOS Incidents ({activeSOSList.length})</span>
              <span className="text-xs font-normal text-slate-400">Zero-refresh push</span>
            </h2>

            {activeSOSList.length === 0 ? (
              <p className="text-sm text-slate-400 py-8 text-center">
                No active SOS signals in range. Waiting for emergency broadcast...
              </p>
            ) : (
              <div className="space-y-3">
                {activeSOSList.map((sos) => (
                  <div
                    key={sos.sos_id}
                    className="bg-slate-900/60 border border-slate-700/80 rounded-xl p-4 flex items-center justify-between"
                  >
                    <div>
                      <div className="flex items-center gap-2 mb-1">
                        <span className="font-mono text-xs text-slate-400">{sos.sos_id}</span>
                        <span
                          className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${
                            sos.status === 'ACCEPTED'
                              ? 'bg-emerald-500/20 text-emerald-300'
                              : 'bg-red-500/20 text-red-300'
                          }`}
                        >
                          {sos.status}
                        </span>
                      </div>
                      <p className="text-sm font-semibold text-white">{sos.category} - {sos.description}</p>
                      <p className="text-xs text-slate-400 mt-0.5">
                        Coords: {sos.latitude}, {sos.longitude}
                      </p>
                    </div>

                    {sos.status === 'PENDING' && (
                      <button
                        onClick={() => handleAcceptSOS(sos)}
                        className="bg-red-600 hover:bg-red-500 text-white font-bold px-3.5 py-1.5 rounded-lg text-xs"
                      >
                        Accept
                      </button>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Right Column: Live Telemetry & Event Log */}
        <div className="space-y-6">
          <div className="bg-slate-800/60 rounded-2xl border border-slate-700 p-5">
            <h3 className="text-sm font-bold uppercase tracking-wider text-slate-400 mb-3">
              Responder Node Info
            </h3>
            <div className="space-y-2 text-xs">
              <div className="flex justify-between py-1 border-b border-slate-700/50">
                <span className="text-slate-400">Device ID</span>
                <span className="font-mono text-white">{userId}</span>
              </div>
              <div className="flex justify-between py-1 border-b border-slate-700/50">
                <span className="text-slate-400">Current Position</span>
                <span className="font-mono text-white">
                  {coords.lat.toFixed(4)}, {coords.lng.toFixed(4)}
                </span>
              </div>
              <div className="flex justify-between py-1 border-b border-slate-700/50">
                <span className="text-slate-400">Search Radius</span>
                <span className="text-emerald-400 font-semibold">150 km</span>
              </div>
            </div>
          </div>

          <div className="bg-slate-800/60 rounded-2xl border border-slate-700 p-5 flex flex-col h-[380px]">
            <h3 className="text-sm font-bold uppercase tracking-wider text-slate-400 mb-2">
              Live Mesh Event Stream
            </h3>
            <div className="flex-1 overflow-y-auto space-y-1.5 font-mono text-[11px] text-slate-300 pr-1">
              {logs.map((log, idx) => (
                <div key={idx} className="p-1 rounded bg-slate-900/40 border border-slate-800">
                  {log}
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
