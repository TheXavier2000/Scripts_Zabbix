Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "Prueba GUI Zabbix"
$form.Size = New-Object System.Drawing.Size(800,500)
$form.StartPosition = "CenterScreen"

# Panel izquierdo
$panelLeft = New-Object System.Windows.Forms.Panel
$panelLeft.Width = 200
$panelLeft.Dock = "Left"
$panelLeft.BackColor = "LightGray"

$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Dock = "Fill"
$listBox.Items.AddRange(@("Operacion 1","Operacion 2","Operacion 3"))

$panelLeft.Controls.Add($listBox)
$form.Controls.Add($panelLeft)

# Panel derecho
$panelRight = New-Object System.Windows.Forms.Panel
$panelRight.Width = 200
$panelRight.Dock = "Right"
$panelRight.BackColor = "WhiteSmoke"

$form.Controls.Add($panelRight)

# Panel central
$panelCenter = New-Object System.Windows.Forms.Panel
$panelCenter.Dock = "Fill"

$btn = New-Object System.Windows.Forms.Button
$btn.Text = "Probar"
$btn.Location = New-Object System.Drawing.Point(100,100)

$btn.Add_Click({
    [System.Windows.Forms.MessageBox]::Show("Funciona 🎉")
})

$panelCenter.Controls.Add($btn)
$form.Controls.Add($panelCenter)

$form.ShowDialog()