<#macro emailLayout>
<html>
<body style="margin:0;padding:0;background:#f4f7fb;font-family:Arial,Helvetica,sans-serif;color:#383838;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f7fb;padding:32px 0;">
    <tr>
      <td align="center">
        <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:8px;border-top:4px solid #012c64;">
          <tr>
            <td style="padding:24px 32px 8px;font-size:22px;font-weight:bold;color:#012c64;">HansaCore</td>
          </tr>
          <tr>
            <td style="padding:8px 32px 32px;font-size:15px;line-height:1.5;">
              <#nested>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
</#macro>
