set SynModuleInfo {
  {SRCNAME TinyYOLOHW MODELNAME TinyYOLOHW RTLNAME TinyYOLOHW IS_TOP 1
    SUBMODULES {
      {MODELNAME TinyYOLOHW_control_s_axi RTLNAME TinyYOLOHW_control_s_axi BINDTYPE interface TYPE interface_s_axilite}
      {MODELNAME TinyYOLOHW_regslice_both RTLNAME TinyYOLOHW_regslice_both BINDTYPE interface TYPE adapter IMPL reg_slice}
      {MODELNAME TinyYOLOHW_flow_control_loop_pipe RTLNAME TinyYOLOHW_flow_control_loop_pipe BINDTYPE interface TYPE internal_upc_flow_control INSTNAME TinyYOLOHW_flow_control_loop_pipe_U}
    }
  }
}
