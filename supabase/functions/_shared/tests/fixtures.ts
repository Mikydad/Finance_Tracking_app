// Bank SMS fixtures, copied verbatim from the anonymized samples in the
// project's sms_samples.md (names, accounts and references are fake; amounts
// and fees are real). Ids match that file. Do not edit the texts: they are
// the formats the parsers must keep handling.

export interface SmsFixture {
  id: string;
  sender: string;
  text: string;
  /** true when the text was written for a test, not copied from a real SMS. */
  synthetic?: boolean;
}

export const SMS: Record<string, SmsFixture> = {
  B1: {
    id: "B1",
    sender: "BOA",
    text:
      "Dear Abebe, your account 7*****45 was debited with ETB 25,018.00. Available Balance: ETB 40,288.78.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26274R7KPN81047\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=DFT26274R7KPN\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect\nFor help, call 8397 (24/7 Toll-Free).\nBank of Abyssinia.",
  },
  B2: {
    id: "B2",
    sender: "BOA",
    text:
      "Dear Abebe, your account 7*****45 was debited with ETB 2,010.80. Available Balance: ETB 73,186.36.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26267JN5TB81047\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=DFT26267JN5TB\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect\nFor help, call 8397 (24/7 Toll-Free).\nBank of Abyssinia.",
  },
  B3: {
    id: "B3",
    sender: "BOA",
    text:
      "Dear Abebe, your account 7*****45 was credited with ETB 186.80 by Credit Int From Another Acc. Available Balance: ETB 65,305.67.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=318264095-20260930\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=C318264095-20260930\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect\nFor help, call 8397 (24/7 Toll-Free).\nBank of Abyssinia.",
  },
  B4: {
    id: "B4",
    sender: "BOA",
    text:
      "...is successful., your account 7*****45 was debited with ETB ...00. Available Balance: ETB ...\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26264...",
  },
  C1: {
    id: "C1",
    sender: "CBE",
    text:
      "Dear Abebe Kebede Tadesse You have received ETB 100,000.00 from account 1********5521 (Tekle G/mariam Berhe) to your account 1********1234. Your current balance is ETB103,674.03. Thanks for Banking with CBE. https://mbreciept.cbe.com.et/v2-hfHCxHa8Rk2LmPq7Wn  for feedback: https://forms.gle/kGNGQpG3mQCCk3iD6",
  },
  C2: {
    id: "C2",
    sender: "CBE",
    text:
      "Dear  Abebe Kebede Tadesse You have successfully transferred ETB100000.00 from account 1********1234 to account 1********3307 (Kidus Alemayehu Desta). Service charge of ETB 5.00 and VAT(15%) of ETB0.75 and Disaster Recovery(5%) of 0.25 with total of ETB100006.00 .Your current balance is ETB-96,331.97. Thanks for Banking with CBE. https://mbreciept.cbe.com.et/v2-hfHCxHb3Tz9QeYv4Ks  for feedback: https://forms.gle/kGNGQpG3mQCCk3iD6",
  },
  C3: {
    id: "C3",
    sender: "CBE",
    text:
      "Dear Abebe Kebede Tadesse You have received ETB 25,000.00 from account 1********6649 (Selam Worku Abebe) to your account 1********1234. Your current balance is ETB33,412.50. Thanks for Banking with CBE. https://mbreciept.cbe.com.et/v2-hfHCxHc7Uw1NdFr8Gj  for feedback: https://forms.gle/kGNGQpG3mQCCk3iD6",
  },
  C4: {
    id: "C4",
    sender: "CBE",
    text:
      "Dear  Abebe Kebede Tadesse You have successfully transferred ETB2100.00 from account 1********1234 to account 1********9081 (Nova Health Services P.l.c). Service charge of ETB 1.00 and VAT(15%) of ETB0.15 and Disaster Recovery(5%) of 0.05 with total of ETB2101.20 .Your current balance is ETB31,311.30. Thanks for Banking with CBE. https://mbreciept.cbe.com.et/v2-hfHCxHd2Vy6PaHs3Lm  for feedback: https://forms.gle/kGNGQpG3mQCCk3iD6",
  },
  C5: {
    id: "C5",
    sender: "CBE",
    text:
      "Dear Abebe Kebede Tadesse A debit transaction of ETB 25000.0. has occurred on your account 1********1234. Service charge of ETB 15.00 and VAT(15%) of ETB2.25 and Disaster Recovery(5%) of 0.75 with total of ETB25018.00 .Your current balance is ETB6,293.30. Thanks for Banking with CBE. https://mbreciept.cbe.com.et/v2-hfHCxHe5Wx4RbJt9Np  for feedback: https://forms.gle/kGNGQpG3mQCCk3iD6",
  },
  C6: {
    id: "C6",
    sender: "CBE",
    text:
      "Dear Abebe Kebede Tadesse A debit transaction of ETB 10620.0. has occurred on your account 1********1234. Service charge of ETB 0.00 and VAT(15%) of 0.0 and Disaster Recovery(5%) of 0.00 with total of ETB10620.00 .Your current balance is ETB3,673.30. Thanks for Banking with CBE. https://mbreciept.cbe.com.et/v2-hfHCxHf8Xa2SgKu5Qr  for feedback: https://forms.gle/kGNGQpG3mQCCk3iD6",
  },
  C7: {
    id: "C7",
    sender: "CBE",
    text:
      "Dear Mr Abebe your Account 1********1234 has been credited with ETB 8000.00. Your Current Balance is ETB 14293.30. Thank you for Banking with CBE! for Reciept https://apps.cbe.com.et:100/BranchReceipt/FT26273XKD4P&12341234",
  },
  C8: {
    id: "C8",
    sender: "CBE",
    text: "Dear Abebe Kebede Tadese, ETB 10620.00 is paid on 30 Sep, 2026 for Loan Id 175904.\nCBE Fast Loan.",
  },
  O1: {
    id: "O1",
    sender: "CBO",
    text:
      "Dear Customer your Account ****6612 has been Debited with ETB5000.00 Service Charge of ETB20 and VAT(15%) of ETB3.00 a Total amount of   5023.00  Ref: FT26271MQ8RD ON 28 SEP 2026 14:58 TO OMNI Banks Payable. Your Current Balance is ETB 142608.25.",
  },
  O2: {
    id: "O2",
    sender: "CBO",
    text:
      "Dear Customer,\nYour One-Time Password (OTP) is 40917 XqLmRtvBnoP\nZ+7kWHaE2sJd. Please, don't share OTP with anyone for security reason.\nIf you didn't initiate this request, please call 609. Thank you!",
  },
  T1: {
    id: "T1",
    sender: "127",
    text:
      "Dear Abebe\nYou have transferred ETB 475.00 to Hana Girma (2519****1122) on 05/10/2026 21:05:39. Your transaction number is DJ50KQ3RTA. The service fee is ETB 1.74 and  15% VAT on the service fee is ETB 0.26. Your current E-Money Account  balance is ETB 0.00. To download your payment information please click this link: https://transactioninfo.ethiotelecom.et/receipt/DJ50KQ3RTA.\n\nThank you for using telebirr\nEthio telecom",
  },
  T2: {
    id: "T2",
    sender: "127",
    text:
      "Dear Abebe\nYou have transferred ETB 580.00 to Hana Girma (2519****1122) on 04/10/2026 20:28:26. Your transaction number is DJ40MB7WXE. The service fee is ETB 3.48 and  15% VAT on the service fee is ETB 0.52. Your current E-Money Account  balance is ETB 5,566.04. To download your payment information please click this link: https://transactioninfo.ethiotelecom.et/receipt/DJ40MB7WXE.\n\nThank you for using telebirr\nEthio telecom",
  },
  T3: {
    id: "T3",
    sender: "127",
    text:
      "Dear Abebe\nYou have transferred ETB 60.00 to YONAS ALEMU (2519****4410) on 04/10/2026 19:32:22. Your transaction number is DJ42PH8CNV. The service fee is ETB 0.87 and  15% VAT on the service fee is ETB 0.13. Your current E-Money Account  balance is ETB 6,652.04. To download your payment information please click this link: https://transactioninfo.ethiotelecom.et/receipt/DJ42PH8CNV.\n\nThank you for using telebirr\nEthio telecom",
  },
  T4: {
    id: "T4",
    sender: "127",
    text:
      "Dear Abebe\nYou have transferred ETB 500.00 to SAMUEL HAILE (2519****8803) on 04/10/2026 20:24:56. Your transaction number is DJ41TZ6LMQ. The service fee is ETB 1.74 and  15% VAT on the service fee is ETB 0.26. Your current E-Money Account  balance is ETB 6,150.04. To download your payment information please click this link: https://transactioninfo.ethiotelecom.et/receipt/DJ41TZ6LMQ.\n\nThank you for using telebirr\nEthio telecom",
  },
  T5: {
    id: "T5",
    sender: "127",
    text:
      "Dear Abebe\nYou have paid ETB 5,200.00 for Service Fee from 412763 - MERON TESFAYE BEKELE on 05/10/2026 14:37:10. Your transaction number is  DJ54RW2HXK. Your current balance is ETB 0.00. To download your payment information please click this link: https://transactioninfo.ethiotelecom.et/receipt/DJ54RW2HXK\nThank you for using telebirr\nEthio telecom",
  },
  T6: {
    id: "T6",
    sender: "127",
    text:
      "Dear Abebe\nYour transaction is successfully completed using Endekise. You have used ETB 481.77 credit amount on this transaction. The service fee is ETB 12.04 and the daily fee will be 9.62 depending on your credit limit. Your outstanding amount is ETB 1523.40 with due date of 2026-11-05 00:00:00. Your Contract number is 40217753.\nThank you for using telebirr\nEthio telecom in partnership with Dashen Bank",
  },
  T7: {
    id: "T7",
    sender: "127",
    text:
      "...125.00 bonus that is used for airtime and package purchase.\nYour current bonus account ... is ETB 125.0...\nThank you for using\nEthio telecom",
  },
  B4_FULL: {
    id: "B4_FULL",
    sender: "BOA",
    synthetic: true,
    text:
      "Your transfer is successful., your account 7*****45 was debited with ETB 1,500.00. Available Balance: ETB 13,770.78.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26264QW8ER81047\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=DFT26264QW8ER\nBank of Abyssinia.",
  },
  B5: {
    id: "B5",
    sender: "BOA",
    synthetic: true,
    text:
      "ውድ ABEBE TADESSE ፣ በአቢሲንያ ሞባይል ባንኪንግ እስከ 100,000 ብር ብድር ያመልክቱ። https://bit.ly/BOAmobilebanking https://bit.ly/BOAmobilebankingA ለእርዳታ 8397",
  },
  B6: {
    id: "B6",
    sender: "BOA",
    synthetic: true,
    text: "ውድ ደንበኛችን ፣ ባንኩ የይለፍ ቃልዎን በአጭር መልዕክት ወይም በስልክ አይጠይቅም። አጠራጣሪ ሊንኮችን አይክፈቱ።",
  },
  C9: { id: "C9", sender: "CBE", synthetic: true, text: "ውድ ደንበኛችን ፣ እንኳን ለመስቀል በዓል በሰላም አደረሳችሁ! ኢትዮጵያ ንግድ ባንክ" },
  T_RECEIVED: {
    id: "T_RECEIVED",
    sender: "127",
    synthetic: true,
    text:
      "Dear Abebe\nYou have received ETB 1,000.00 from Hana Girma(2519****1122) on 06/10/2026 09:15:02. Your transaction number is DJ61ZX4QPL. Your current E-Money Account  balance is ETB 1,000.00.\nThank you for using telebirr\nEthio telecom",
  },
  UNKNOWN_BANK: {
    id: "UNKNOWN_BANK",
    sender: "AWASH",
    synthetic: true,
    text:
      "Dear Customer, your account 01320****5678 has been debited with ETB 750.00 on 05/10/2026. Ref: TT26278ABC12. Awash Bank",
  },
};
