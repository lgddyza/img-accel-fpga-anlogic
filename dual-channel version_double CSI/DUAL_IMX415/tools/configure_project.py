"""Register V2 files and physical constraints, leaving the V1 tree untouched."""
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'dual_imx415.al'
# TD uses an XML-like custom reader (literal '&', '::' tags, exact empty
# elements). Preserve its original formatting rather than normalize as XML.
baseline=ROOT/'docs/v1_project_reference.al'
s=baseline.read_text(encoding='utf-8-sig')
s=re.sub(r'(<Project[^>]* Path=")[^"]+',lambda m:m[1]+ROOT.as_posix(),s,count=1)
s=s.replace('<Name>fpga_prj_jpeg</Name>','<Name>dual_imx415</Name>')
s=s.replace('>system_top<','>dual_imx415_top<')
s=re.sub(r'            <File Path="uisrc/01_rtl/system_top.v">.*?</File>\s*','',s,flags=re.S)
s=re.sub(r'            <File Path="uisrc/03_ip/dsi/[^"]+">.*?</File>\s*','',s,flags=re.S)
# The new board uses the complete official HS-only core; remove old LP PHY definitions.
s=re.sub(r'[ \t]*<File Path="uisrc/03_ip/al_ip/mipi_rx/[^"]+">.*?</File>\s*','',s,flags=re.S)
entries=[]
for order,f in enumerate(sorted((ROOT/'rtl').glob('*.v')),200):
 path=f.relative_to(ROOT).as_posix()
 entries.append(f'''            <File Path="{path}">
                <FileInfo>
                    <Attr Name="AutoExcluded" Val="false"/>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="{order}"/>
                </FileInfo>
            </File>''')
s=s.replace('        </Verilog>','\n'.join(entries)+'\n        </Verilog>',1)
# The profile-selectable I2C controller references both register tables.
# Register the official 37.125 MHz table explicitly in the generated project.
profile_entry = '''            <File Path="uisrc/03_ip/ui_imx415_cfg/ui_imx415_reg_37125.v">
                <FileInfo>
                    <Attr Name="AutoExcluded" Val="false"/>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="11"/>
                </FileInfo>
            </File>'''
s=s.replace('        </Verilog>', profile_entry+'\n'+'\n'.join(profile_entry.replace('ui_imx415_cfg/ui_imx415_reg_37125.v','mipi_csi_2/'+f.name).replace('Val="11"','Val="'+str(300+i)+'"') for i,f in enumerate(sorted((ROOT/'uisrc/03_ip/mipi_csi_2').glob('*.v'))))+'\n        </Verilog>',1)
p.write_text(s,encoding='utf-8')
# A distinct entry prevents an already-open TD window with the old file list
# from overwriting the new profile registration when it saves its project.
(ROOT/'dual_imx415_37125.al').write_text(
 s.replace('<Name>dual_imx415</Name>','<Name>dual_imx415_37125</Name>'),encoding='utf-8')
(ROOT/'dual_imx415_hsfix.al').write_text(s.replace('<Name>dual_imx415</Name>','<Name>dual_imx415_hsfix</Name>'),encoding='utf-8')
adc=['# V2 FMC mapping: official HS-only CSI receiver. No LP input pins.',
     '# No old DSI outputs are present. Companion HS N pin is implicit in LVDS primitive.']
def pin(name,ball,standard='LVCMOS18',extra='PULLTYPE = NONE;'):
 adc.append(f'set_pin_assignment {{ {name} }} {{ LOCATION = {ball}; IOSTANDARD = {standard}; {extra} }}')
pin('I_sysclk_25m','T16',extra='PULLTYPE = PULLUP;')
pin('I_ddr_clk','T13','LVDS18');pin('pcie_mperst','U14',extra='PULLTYPE = PULLUP;')
pin('O_cam_refclk','K16',extra='DRIVESTRENGTH = 8; PULLTYPE = NONE;')
for cam,clk,hs,lp,scl,sda,pwd in [
 ('a','C14',['A13','G14','F18','F15'],[('C15','D15'),('H16','H15'),('A14','B14'),('B16','C16')],'J13','K13','K17'),
 ('b','E13',['C17','H14','J17','D18'],[('A15','A16'),('D17','E17'),('A18','B18'),('N11','N10')],'G17','G16','K15')]:
 pin(f'I_cam_{cam}_clk_hs',clk,'LVDS18')
 for i,ball in enumerate(hs): pin(f'I_cam_{cam}_data_hs[{i}]',ball,'LVDS18','PULLTYPE = NONE; INDEL = 20;')
 pin(f'O_cam_{cam}_scl',scl,extra='DRIVESTRENGTH = 8; PULLTYPE = PULLUP;')
 pin(f'IO_cam_{cam}_sda',sda,extra='DRIVESTRENGTH = 8; PULLTYPE = PULLUP;')
 pin(f'O_cam_{cam}_pwdnb',pwd,extra='DRIVESTRENGTH = 8; PULLTYPE = NONE;')
(ROOT/'uisrc/04_pin/fpga_pin.adc').write_text('\n'.join(adc)+'\n',encoding='utf-8')
sdc='''# V2 independent forwarded clocks, not a muxed camera clock.
create_clock -name sys_clk -period 40.000 [get_ports I_sysclk_25m]
create_clock -name ddr_clk -period 10.000 [get_ports I_ddr_clk]
# Official IMX415 SYS_MODE=5 profile: 891 Mbps/lane, forwarded clock 445.5 MHz.
create_clock -name mipi_a -period 2.24467 [get_ports I_cam_a_clk_hs]
create_clock -name mipi_b -period 2.24467 [get_ports I_cam_b_clk_hs]
derive_clocks
rename_clock -name cfg_clk [get_clocks {X_ui_pll/pll_inst.clkc[1]}]
rename_clock -name lp_clk [get_clocks {X_ui_pll/pll_inst.clkc[0]}]
rename_clock -name pcie_core_src [get_clocks {u_pcie/u_sgdma_pll/pll_inst.clkc[0]}]
rename_clock -name pcie_aux [get_clocks {u_pcie/u_sgdma_pll/pll_inst.clkc[1]}]
rename_clock -name jpeg_enc [get_clocks {u_pcie/u_jpeg_clk_pll/pll_inst.clkc[0]}]
'''
sdc+='''set_clock_groups -asynchronous \\
    -group [get_clocks {sys_clk cfg_clk lp_clk pcie_core_src pcie_aux}] \\
    -group [get_clocks {ddr_clk u_ddr/X_ui_ddr/dfi_clk u_ddr/X_ui_ddr/mcu_clk u_ddr/X_ui_ddr/ref_clk}] \\
    -group [get_clocks {jpeg_enc}] \\
    -group [get_clocks -include_generated_clocks {mipi_a}] \\
    -group [get_clocks -include_generated_clocks {mipi_b}] \\
    -group [get_clocks {u_pcie/u_sgdma_subsys/DEVICE_IS_PH1A$u_ph1a_if_ep/PH1A_PCIE_CORE_BLK$u_al_pcie_ip/pcie_user_clk u_pcie/u_sgdma_subsys/DEVICE_IS_PH1A$u_ph1a_if_ep/PH1A_PCIE_CORE_BLK$u_al_pcie_ip/core_clk}]
'''
sdc+='''
# Only cfg_clk -> the two named reset-synchronizer banks is asynchronous.
# The register selector survives hierarchy flattening (module input pins do not).
# cfg_clk reaches only their async reset pins; D inputs are constants/lp_clk stages.
# Preserve lp_clk stage-to-stage paths and all synchronizer-output recovery checks.
set_false_path -from [get_clocks cfg_clk] -to [get_regs {u_camera_a/u_ref_reset/stages*}]
set_false_path -from [get_clocks cfg_clk] -to [get_regs {u_camera_b/u_ref_reset/stages*}]
'''
(ROOT/'uisrc/04_pin/timing.sdc').write_text(sdc,encoding='utf-8')
print('V2 HS-only project entries and ADC/SDC updated')
